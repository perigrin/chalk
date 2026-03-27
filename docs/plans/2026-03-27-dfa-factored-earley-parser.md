# A DFA-Factored Earley Parser with Composite Semiring Disambiguation

**A design for parsing ambiguous grammars efficiently through precomputed
state machines, distance-factored chart representation, and type-directed
disambiguation.**

**Version**: 0.1 (Draft)
**Date**: 2026-03-27
**Status**: Design

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Earley Parsing](#2-earley-parsing)
3. [The Perl Type System](#3-the-perl-type-system)
4. [Disambiguation via Semiring Composition](#4-disambiguation-via-semiring-composition)
5. [LR(0) DFA Construction](#5-lr0-dfa-construction)
6. [Distance Factoring](#6-distance-factoring)
7. [The Operation Table](#7-the-operation-table)
8. [The Parse Loop](#8-the-parse-loop)
9. [Error Detection, Diagnostics, and Recovery](#9-error-detection-diagnostics-and-recovery)
10. [Grammar Construction and BNF Bootstrap](#10-grammar-construction-and-bnf-bootstrap)
11. [Code Generation Pipeline](#11-code-generation-pipeline)
12. [Performance Analysis](#12-performance-analysis)

Appendices:
- [A: Example BNF Grammar](#appendix-a-example-bnf-grammar)
- [B: Full Worked Trace](#appendix-b-full-worked-trace)
- [C: Glossary](#appendix-c-glossary)

---

## 1. Introduction

### The Problem

Consider a compiler for a subset of Perl 5. The grammar has 65 rules
covering expressions, statements, declarations, control flow, and
object-oriented constructs. The grammar is deliberately ambiguous:
`{ $x }` could be a hash constructor or a block; `push @a, $x . $y`
could group as `push(@a, $x . $y)` or `(push @a) . $x . $y`; the
word `class` could be a keyword or an identifier depending on context.

A standard Earley parser handles ambiguous grammars correctly — it
explores all possible parse trees in parallel. But it explores too
many. For a 1,000-line source file, the parser processes 50,000+
character positions. At each position, it maintains an agenda of
hundreds of active parse items, performs regex matching against dozens
of terminal patterns, and calls disambiguation logic for every
alternative. The result is correct but slow: minutes per file,
dominated by bookkeeping rather than useful work.

This paper describes a parser that eliminates most of that bookkeeping.
It combines three techniques:

1. **LR(0) DFA state machines** (Aycock, 2001) — precompute all
   structural parsing decisions at grammar construction time. Prediction,
   terminal matching, and completion routing become table lookups instead
   of per-item computation.

2. **Distance factoring** (Makarov/YAEP, 2002) — separate the
   grammar-structural part of an Earley set (which rules are active)
   from the input-specific part (where each rule started). Two parse
   positions with the same active rules share the structural work;
   only the distances differ.

3. **Composite semiring disambiguation** — four semirings collaborate
   to resolve ambiguity at parse time: Boolean recognition, operator
   precedence, a formal type system with operator return type inference,
   and structural preference tagging. A fifth semiring constructs the
   output IR. Each semiring's contribution to a DFA state is a column
   in an operation table — data, not code.

The combination transforms the parser from an interpreter (reading the
grammar and deciding what to do at each position) into a table-driven
machine (looking up precomputed decisions and applying them to
position-specific values). The grammar determines the tables. The input
determines the values. The two never mix at runtime.

### Prior Art

**Earley (1970)** introduced the chart parsing algorithm that handles
all context-free grammars, including ambiguous ones. Its worst case is
O(n^3) for ambiguous grammars, O(n^2) for unambiguous, and O(n) for
LR(k) grammars — but with large constant factors from per-item object
allocation, hash-based chart membership, and redundant prediction work.

**Aycock and Horspool (2002)** showed that an LR(0) DFA constructed
from the grammar can replace Earley's Predictor step entirely. The DFA
precomputes which items will be predicted for each nonterminal,
eliminating per-position prediction computation. Their dissertation
also introduced safe-set GC (freeing chart positions that can no longer
participate in completions), bitmap-based chart membership, and terminal
clustering per DFA state.

**Makarov (YAEP, 2002)** took a different approach: factor each Earley
set into a *core* (the set of active grammar items, independent of
position) and *distances* (where each item started, relative to the
current position). Cores are hash-consed and shared across positions.
When a new position produces the same core as a previous one — common
in repetitive source code — the parser reuses the core's structural
work and only threads new distance values through it.

**Goodman (1999)** formalized the semiring framework for parsing,
showing that different "interpretations" of a grammar (recognition,
counting, probability, tree construction) can be expressed as semiring
operations applied uniformly by the parser. This paper extends Goodman's
framework with four disambiguation semirings that collaborate to resolve
ambiguity in real programming language grammars.

**Prather (2026)** formalized Perl's latent type system through
syntactic preservation and semantic fulfillment, providing the
theoretical foundation for the type inference semiring described in
Section 3.

### What This Paper Covers

This paper specifies the complete pipeline from grammar definition to
compiled output:

- **Sections 2-4**: The parsing algorithm, the type system, and the
  semiring architecture. These sections provide the conceptual
  foundation.
- **Sections 5-8**: The DFA construction, distance factoring, operation
  tables, and the parse loop. These sections specify the implementation.
- **Section 9**: Error handling — detection, diagnostics, and recovery.
- **Section 10**: Grammar construction and the BNF bootstrap path.
- **Section 11**: The code generation pipeline from parse result to
  compiled C output.
- **Section 12**: Performance analysis and complexity bounds.

Each concept is introduced with a toy arithmetic grammar, then applied
to a realistic Perl subset grammar. Appendix B traces a complete parse
of a 5-line Perl program through all phases.

The specification is language-independent. An implementer could build
this parser in Perl, C, Rust, or any language with hash tables and
arrays. The type system and grammar are Perl-specific; the parsing
algorithm is not.

---

## 2. Earley Parsing

This section describes the standard Earley algorithm. Readers familiar
with Earley parsing may skip to Section 2.5 (Limitations), which
motivates the DFA-factored design.

### 2.1 Grammars, Rules, and Symbols

A grammar is a list of *rules*. Each rule has a *name* (also called the
left-hand side or nonterminal) and one or more *alternatives* (also
called right-hand sides or productions). Each alternative is a sequence
of *symbols*.

A symbol is either a *terminal* (a pattern that matches input text) or
a *reference* (a nonterminal that refers to another rule by name).

Example — a grammar for arithmetic expressions:

```
Expr   ::= Expr '+' Term
          | Term
Term   ::= 'number'
```

Here `Expr` and `Term` are nonterminals. `'+'` and `'number'` are
terminals. `Expr` has two alternatives: `Expr '+' Term` and `Term`.

Terminals are regular expression patterns anchored at the current parse
position. The terminal `'number'` might match the regex `\d+`. The
terminal `'+'` matches the literal character `+`. The parser tries each
terminal pattern at the current position and advances past the matched
text.

A grammar is *ambiguous* when the same input can be parsed in multiple
ways. The arithmetic grammar above is unambiguous (left-recursive `Expr`
forces left-associative grouping). But a grammar for real Perl code is
deliberately ambiguous — the parser explores all alternatives and the
semiring system (Section 4) resolves the ambiguity.

### 2.2 Earley Items

An *Earley item* is a triple:

```
[rule_name, alt_index, dot] @ origin
```

- `rule_name`: which grammar rule this item belongs to
- `alt_index`: which alternative of the rule
- `dot`: how far through the alternative we have matched (0 = beginning)
- `origin`: the input position where this item began matching

The dot divides the alternative into a matched prefix and an unmatched
suffix. For the rule `Expr ::= Expr '+' Term` with dot=1 at origin 0:

```
[Expr, 0, 1] @ 0    means    Expr -> Expr . '+' Term
```

The parser has matched `Expr` and expects `'+'` next.

An item is *complete* when the dot reaches the end of its alternative:

```
[Expr, 0, 3] @ 0    means    Expr -> Expr '+' Term .
```

The parser has matched the entire alternative.

### 2.3 The Chart

The *chart* is an array of *Earley sets*, one per input position (0
through N, where N is the input length). Each set contains the items
active at that position.

```
chart[0] = { [Expr, 0, 0] @ 0,  [Expr, 1, 0] @ 0,  [Term, 0, 0] @ 0 }
chart[1] = { ... }
...
chart[N] = { ... }
```

The parse succeeds when `chart[N]` contains a complete item for the
start rule with origin 0:

```
[start_rule, any_alt, end_dot] @ 0   in chart[N]
```

### 2.4 The Three Operations

The parser processes each chart position using three operations:

**Predict.** When an item's dot is before a nonterminal reference, add
items for every alternative of that nonterminal at the current position.

If `chart[pos]` contains `[A, i, k] @ j` and symbol k of alternative i
is a reference to nonterminal B, then for each alternative m of B, add:

```
[B, m, 0] @ pos
```

Prediction seeds the chart with items for rules that *might* match
starting here.

**Scan.** When an item's dot is before a terminal, try to match the
terminal pattern against the input at the current position. If it
matches, advance the dot and place the new item at the position after
the match.

If `chart[pos]` contains `[A, i, k] @ j` and symbol k is a terminal
that matches text from `pos` to `end_pos`, then add:

```
[A, i, k+1] @ j    to chart[end_pos]
```

Scanning consumes input text and advances the parse.

**Complete.** When a complete item exists at the current position, find
all items at the *origin* position that were waiting for this rule to
complete, and advance their dots.

If `chart[pos]` contains `[B, m, end] @ origin` (complete), and
`chart[origin]` contains `[A, i, k] @ j` where symbol k is a reference
to B, then add:

```
[A, i, k+1] @ j    to chart[pos]
```

Completion propagates results backward: "B finished parsing from
`origin` to `pos`, so any rule that was waiting for B at `origin` can
now advance past it."

### 2.5 Worked Example: Arithmetic

Parse the input `2+3` with the grammar:

```
Expr   ::= Expr '+' Term    (alt 0)
          | Term             (alt 1)
Term   ::= 'number'         (alt 0)
```

Terminals: `'number'` matches `\d+`, `'+'` matches literal `+`.

**chart[0]** — position 0 (before `2`):
```
Predict from start rule:
  [Expr, 0, 0] @ 0          Expr -> . Expr '+' Term
  [Expr, 1, 0] @ 0          Expr -> . Term
Predict Expr (from Expr alt 0):
  (already present)
Predict Term (from Expr alt 1):
  [Term, 0, 0] @ 0          Term -> . 'number'
Scan 'number' matches "2" (pos 0..1):
  [Term, 0, 1] @ 0          goes to chart[1]
```

**chart[1]** — position 1 (after `2`, before `+`):
```
  [Term, 0, 1] @ 0          Term -> 'number' .       (complete!)
Complete Term (origin=0):
  [Expr, 1, 1] @ 0          Expr -> Term .            (complete!)
  also advance Expr alt 0:
  [Expr, 0, 1] @ 0          Expr -> Expr . '+' Term
Complete Expr (origin=0):
  (Expr alt 0 already waiting — but Expr isn't before the dot here)
Scan '+' matches "+" (pos 1..2):
  [Expr, 0, 2] @ 0          goes to chart[2]
```

**chart[2]** — position 2 (after `+`, before `3`):
```
  [Expr, 0, 2] @ 0          Expr -> Expr '+' . Term
Predict Term:
  [Term, 0, 0] @ 2          Term -> . 'number'
Scan 'number' matches "3" (pos 2..3):
  [Term, 0, 1] @ 2          goes to chart[3]
```

**chart[3]** — position 3 (after `3`, end of input):
```
  [Term, 0, 1] @ 2          Term -> 'number' .       (complete!)
Complete Term (origin=2):
  [Expr, 0, 3] @ 0          Expr -> Expr '+' Term .  (complete!)
```

The start rule `Expr` is complete at chart[3] with origin 0. The parse
succeeds. The parser matched `2+3` as `Expr -> Expr '+' Term`, where
the left `Expr` matched `2` via `Expr -> Term -> 'number'` and the
right `Term` matched `3` via `Term -> 'number'`.

### 2.6 Handling Ambiguity

When two items with the same `[rule, alt, dot] @ origin` arrive at the
same chart position, the chart merges them. In a standard Earley parser,
"merge" means "keep one, discard the other" or "keep both in a parse
forest." The choice depends on what you want from the parse.

For a compiler, we want exactly one parse tree. The semiring system
(Section 4) resolves this: each item carries a *value* from the
semiring, and when two items merge, the semiring's `add` operation
chooses the winner. Different semirings choose differently — precedence
prefers higher-binding operators, structural tagging prefers blocks over
hashes, and so on.

### 2.7 Limitations of Standard Earley

The standard algorithm has four sources of overhead:

1. **Prediction is per-position.** At every chart position, the parser
   examines each active item, checks whether the dot is before a
   nonterminal, and adds prediction items for that nonterminal's
   alternatives. For a grammar with 65 rules, prediction can add dozens
   of items per position. This work repeats identically at positions
   with the same active rules.

2. **The chart stores objects.** Each item is a data structure (hashref,
   object, tuple) that must be allocated, populated, and hashed for
   membership testing. The allocation and hashing dominate parse time
   for large inputs.

3. **Completion searches the chart.** When a rule completes, the parser
   must find all items at the origin position that were waiting for that
   rule. This requires iterating all items at the origin position or
   maintaining a secondary index.

4. **Terminal matching is per-item.** Each item waiting for a terminal
   triggers an independent regex match attempt. If 20 items expect the
   same terminal pattern, the regex runs 20 times at the same position.

The DFA-factored parser eliminates all four sources of overhead. DFA
states replace per-position prediction (1). Integer-indexed arrays
replace object allocation (2). Precomputed completion maps replace
chart searching (3). Terminal maps replace per-item regex matching (4).

The next two sections describe the type system and semiring architecture
that make disambiguation possible. Section 5 then constructs the DFA
that eliminates the overhead.

---

## 3. The Perl Type System

The parser's TypeInference semiring implements a formal type system for
Perl, based on Prather's formalization (2026). This section describes
the type system independently of the parser, so that the semiring's
behavior in Section 4 has a clear foundation.

### 3.1 Why Types Matter for Parsing

Perl's grammar is ambiguous at the syntactic level. The parser must
distinguish between expressions that look identical in the grammar but
have different meanings. Types resolve many of these ambiguities:

- `push @array, $x` — `push` requires its first argument to be an
  Array. If the parser tries a derivation where `push` takes a Scalar
  first argument, the type check fails and that derivation dies.

- `$x + $y` — the `+` operator requires Num operands and returns Num.
  `$x . $y` requires Str operands and returns Str. If the parser can
  infer that `$x` is Int, it knows `$x + $y` returns Num and `$x . $y`
  coerces `$x` to Str.

- `class` as a keyword vs. identifier — the word `class` in
  `class Foo { }` is a keyword introducing a class declaration. In
  `$obj->class()`, it is a method name (identifier). TypeInference
  rejects the keyword interpretation when no class declaration is
  predicted.

Types also flow upward through the parse tree. When a BinaryExpression
completes, its return type is determined by the operator: `+` returns
Num, `.` returns Str, `==` returns Bool. This return type becomes the
type of the expression in its parent context, enabling further
disambiguation.

### 3.2 The Type Hierarchy

Types are organized in a lattice with subtyping relationships.

```
Any
 |
 +-- Scalar
 |    +-- Undef
 |    +-- Bool
 |    +-- Str
 |    |    +-- Num
 |    |         +-- Int
 |    +-- DualVar
 |    +-- NaN, Inf
 |    +-- Regex
 |    +-- Ref
 |         +-- ScalarRef, ArrayRef, HashRef, CodeRef, GlobRef, Object
 |
 +-- List
 |    +-- Array
 |    +-- Hash
 |
 +-- Code
 +-- Glob

None (bottom type - unreachable)
Unknown (no type information)
```

Subtyping means every value of the child type is also a value of the
parent type:

```
Int  <:  Num  <:  Str  <:  Scalar  <:  Any
```

Every integer is a number. Every number is a string (it can be
stringified). Every string is a scalar.

### 3.3 Bitset Representation

Types are represented as unsigned 32-bit integers. Each leaf type
occupies one bit:

```
Bit 0:  Undef       Bit 8:  ArrayRef    Bit 16: Glob
Bit 1:  Bool        Bit 9:  HashRef     Bit 17: NaN
Bit 2:  Int         Bit 10: CodeRef     Bit 18: Inf
Bit 3:  Num (leaf)  Bit 11: GlobRef
Bit 4:  Str (leaf)  Bit 12: Object
Bit 5:  DualVar     Bit 13: Array
Bit 6:  Regex       Bit 14: Hash
Bit 7:  ScalarRef   Bit 15: Code
```

Parent types are the bitwise OR of their descendants:

```
Num    = bit(3) | bit(2)                          = Int | Num-leaf
Str    = bit(4) | Num                             = Str-leaf | Num | Int
Scalar = Undef | Bool | Str | DualVar | NaN | Inf | Regex | Ref
Any    = Scalar | List | Code | Glob
```

Subtype checking is a single AND operation:

```
IsSubtype(child, parent):  return (parent & child) == child
```

Int is a subtype of Num because `Num & Int == Int` (Int's bit is present
in Num's mask). Int is a subtype of Str because `Str & Int == Int`
(Int's bit is present in Str's mask, since `Str = Str-leaf | Num | Int`).

This representation makes type operations fast — intersection, union,
and subtype checks are single integer operations with no branching.

### 3.4 Type Membership

A value belongs to a type when two conditions hold (Prather 2026):

**Syntactic Preservation.** Converting the value to the type and back
does not change the value. If you take a Perl value, coerce it to a
number, then coerce it back to a string, and get the original string,
then the value preserves its identity through the Num type.

**Semantic Fulfillment.** The value satisfies the operational contracts
of the type. For Num, this includes: `v == v` (reflexivity),
`v - v == 0` (subtraction identity), and closure under arithmetic. The
string `"NaN"` passes the syntactic test (`"NaN"` numifies to NaN,
which stringifies back to `"NaN"`) but fails the semantic test (NaN
does not equal itself), so `"NaN"` is not a member of Num.

For the parser, type membership matters at two points:

1. **Scan time**: when a terminal matches, the scanned text determines
   a type. A digit sequence is Int. A quoted string is Str. A variable
   with `$` sigil is Scalar; with `@` is Array; with `%` is Hash.

2. **Complete time**: when an expression rule completes, the result type
   is inferred from the operator and operand types. The inferred type
   is checked against the parent context's expectations.

### 3.5 Operator and Builtin Signatures

Every operator and builtin function has a typed signature specifying
operand types and return type.

**Binary operators:**

| Operator | Left | Right | Result |
|----------|------|-------|--------|
| `+` `-` `*` `/` `%` `**` | Num | Num | Num |
| `.` | Str | Str | Str |
| `x` | Str | Int | Str |
| `==` `!=` `<` `>` `<=` `>=` | Num | Num | Bool |
| `eq` `ne` `lt` `gt` `le` `ge` | Str | Str | Bool |
| `<=>` `cmp` | Num/Str | Num/Str | Int |
| `&&` `\|\|` `//` `and` `or` | Any | Any | Any |
| `&` `\|` `^` `<<` `>>` | Int | Int | Int |
| `=~` `!~` | Str | Regex | Bool |
| `..` `...` | Int | Int | List |
| `isa` | Scalar | Str | Bool |

**Unary operators:**

| Operator | Operand | Result |
|----------|---------|--------|
| `-` `+` (numeric) | Num | Num |
| `!` `not` | Any | Bool |
| `~` (bitwise) | Int | Int |
| `\` (reference) | Any | Ref |

**Builtin functions (selected):**

| Builtin | Arguments | Return |
|---------|-----------|--------|
| `push` | Array, Any... | Int |
| `pop`, `shift` | Array | Scalar |
| `keys`, `values` | Hash \| Array | List |
| `length` | Str | Int |
| `join` | Str, Str... | Str |
| `split` | Regex, Str, Int? | List |
| `defined` | Scalar | Bool |
| `ref` | Scalar | Str |
| `map`, `grep` | Code, List | List |
| `die` | Str... | None |

The `None` return type for `die` means the function never returns — it
terminates the current execution path.

### 3.6 Type Inference Through the Parse Tree

Type inference proceeds bottom-up through the parse tree:

1. **Leaves** (scan time): terminals receive initial types from the
   matched text. Variable sigils, literal patterns, and operator
   symbols each map to a type.

2. **Unary/Binary expressions** (complete time): the operator signature
   determines the result type. The parser checks that operand types
   satisfy the signature (via `TypeSatisfies`). If they do not, this
   parse path returns zero — it is killed.

3. **Call expressions** (complete time): the builtin signature
   determines the result type. Argument types are checked against the
   signature's `ArgTypes`. Arity is validated against `MinArity`.

4. **Wrapper rules** (complete time): rules like `Expression`,
   `Statement`, `Block` propagate the child's type upward unchanged.

5. **Declaration rules** (complete time): `VariableDeclaration` binds
   the declared variable's type for use in subsequent references.

The type checker is *permissive by default*: when type information is
not available (`Unknown`), the check passes. This ensures the parser
does not reject valid programs due to incomplete type inference. Only
when positive type information contradicts the expected type does the
checker reject a parse path.

### 3.7 TypeSatisfies: The Subtype Check

The subtype check used during parsing accounts for three cases:

```
TypeSatisfies(actual, required):
  1. required == Any              -> true  (anything accepted)
  2. actual == Unknown            -> true  (permissive default)
  3. IsSubtype(actual, required)  -> true  (exact or subtype match)
  4. actual is a polymorphic container (Any, Scalar, List)
     AND IsSubtype(required, actual) -> true
     (a Scalar variable might hold an Int at runtime)
  5. otherwise                    -> false (type mismatch — kill path)
```

Rule 4 handles the common case where a variable is typed as `Scalar`
but the context requires `Int`. Since `Scalar` is a polymorphic
container that might hold an `Int`, the check passes. By contrast, `Str`
is *not* polymorphic — a `Str` variable cannot satisfy an `Int`
requirement, because the string might be `"hello"`.

---

## 4. Disambiguation via Semiring Composition

The parser uses five semirings that compose into a single value threaded
through every parse item. Each semiring answers a different question
about the parse. Together, they resolve all ambiguities in the grammar
and construct the output.

### 4.1 What Is a Semiring (for Parsing)?

A semiring provides four operations that the parser calls at specific
points:

| Operation | When Called | Purpose |
|-----------|------------|---------|
| `one()` | Item creation | The identity value for a new item |
| `zero()` | Rejection | A dead value — this parse path failed |
| `multiply(a, b)` | Sequence | Combine a with the next matched element b |
| `add(a, b)` | Merge | Two items arrived at the same chart cell — pick one |
| `on_scan(v, ...)` | Terminal match | Transform value after scanning terminal text |
| `on_complete(v, ...)` | Rule completion | Transform value after a rule finishes matching |
| `is_zero(v)` | Check | Is this value dead? |
| `should_scan(v, ...)` | Pre-scan gate | Should the parser attempt this scan? |

`multiply` combines values sequentially: "we matched A, then matched B,
so the combined value is multiply(A's value, B's value)."

`add` combines values for the same parse position: "two different
derivations both produced an item at [rule, alt, dot] @ origin — which
value wins?"

`zero` is the annihilator: `multiply(x, zero) = zero` and
`add(x, zero) = x`. When any semiring returns zero, the entire parse
path dies.

### 4.2 The Five Semirings

The parser's composite value is a 5-element tuple:

```
[Boolean, Precedence, TypeInference, Structural, SemanticAction]
```

Each element is the value from one semiring. The composite semiring
(`FilterComposite`) delegates operations to each component and
propagates zeros.

#### 4.2.1 Boolean — Recognition

The simplest semiring. Values are `true` (valid parse path) or a
special zero value (dead path).

- `one()` = `true`
- `zero()` = a unique reference (identity-checked)
- `multiply(a, b)` = `true` if both non-zero, else `zero`
- `add(a, b)` = `true` if either non-zero, else `zero`
- `on_scan(v, ...)` = `v` (transparent)
- `on_complete(v, ...)` = `v` (transparent)

Boolean answers: "does this input match the grammar?" It accepts
everything the grammar can derive. The other semirings narrow the
result.

#### 4.2.2 Precedence — Operator Nesting Validation

Values are hash-consed tuples of `(valid, level, assoc, is_operator)`:

- `level`: the precedence level (0 = tightest binding). Expression-type
  rules have conceptual levels: PostfixExpression = -2,
  UnaryExpression = -1, TernaryExpression = 100,
  AssignmentExpression = 101.
- `assoc`: `'left'`, `'right'`, or `'nonassoc'`.
- `is_operator`: true when this value represents a binary/assignment
  operator (not its operand).

**How it works:**

On scan of a binary operator (e.g., `+` at level 3, left-associative):
the precedence semiring checks the accumulated left-operand value. If
the left operand has a *higher* level number (lower precedence), this
nesting is invalid — kill the path. Example: in `$a && $b + $c`, if the
parser tries to group as `($a && $b) + $c`, the left operand `$a && $b`
has level 10 (logical AND) while `+` has level 3 (arithmetic). Since
10 > 3, the left operand has lower precedence than the operator — this
grouping is rejected.

On completion of expression-type rules: the value carries the expression
type's conceptual level. PostfixExpression at level -2 rejects any
accumulated value with level >= 0 (a bare BinaryExpression cannot be a
postfix target without parentheses).

On add (merge): prefer the value with the most constraining (highest)
precedence level. This ensures the tightest possible constraint flows
to subsequent operator checks.

Parenthesized expressions (ParenExpr) reset the precedence to `one()`,
clearing all accumulated constraints.

#### 4.2.3 TypeInference — The Type System at Parse Time

Values are Context objects carrying a *focus* (a tag hash with type
information) and *children* (for tree structure). The type system from
Section 3 is applied at each step:

**On scan (leaf typing):**
- Variable with `$` sigil → `{type: Scalar}`
- Variable with `@` sigil → `{type: Array}`
- Variable with `%` sigil → `{type: Hash}`
- Integer literal → `{type: Int}`
- Float literal → `{type: Num}`
- String literal → `{type: Str}`
- Regex literal → `{type: Regex}`
- `undef` → `{type: Undef}`
- `true`/`false` → `{type: Bool}`
- Anonymous sub → `{type: CodeRef}`
- Binary operator text → `{op_text: "+"}` (consumed at complete time)

**On complete (type propagation and validation):**

For BinaryExpression: look up the operator's signature from the
`op_text` tag. Check that the left operand's type satisfies the
required left type. Check that the right operand satisfies the required
right type. Set the result type to the operator's return type. If either
check fails, return zero.

```
Example: $x + $y  where $x: Scalar, $y: Int
  Operator: +  requires (Num, Num) -> Num
  TypeSatisfies(Scalar, Num) -> true  (Scalar is polymorphic)
  TypeSatisfies(Int, Num)    -> true  (Int <: Num)
  Result type: Num
```

For UnaryExpression: same pattern with the unary operator signature.

For CallExpression: look up the builtin signature. Validate each
argument's type against the signature's ArgTypes. Validate arity
against MinArity. Set result to ReturnType.

For keyword rejection: when a word like `class` is scanned as a
QualifiedIdentifier, TypeInference checks whether a keyword-consuming
rule (ClassDeclaration) is predicted at this position. If it is, the
identifier interpretation is rejected — `class` is a keyword here, not
a name.

**On multiply:** propagate type tags from left to right. The `type` tag
from a child flows into the parent context.

**On add:** return both alternatives (as an arrayref) for
FilterComposite to resolve. TypeInference does not pick winners — it
provides type information that other semirings use.

#### 4.2.4 Structural — Syntactic Disambiguation

Values are integer bitfields. Each bit represents a structural property:

```
Bit 0: is_block    (completed a Block rule)
Bit 1: is_hash     (completed a HashConstructor)
Bit 2: is_call     (completed a CallExpression)
Bit 3: is_list     (completed an ExpressionList)
Bit 4: is_deref    (completed a PostfixDeref or Subscript)
Bit 5: is_method   (completed a MethodCall)
Bit 6: is_binop    (completed a BinaryExpression)
Bit 7: is_vardecl  (completed a VariableDeclaration)
```

**On complete:** tag the value with the appropriate bit for the
completed rule. Block completions set `is_block`. CallExpression
completions set `is_call` and clear `is_deref`/`is_method` (a direct
call is not a dereference).

**On multiply:** bitwise OR. Tags accumulate through the parse tree.

**On add (merge):** a cascade of preferences resolves structural
ambiguity:
1. Prefer non-list over list (Expression over ExpressionList)
2. Prefer is_call over non-call (CallExpression over bare identifier)
3. Among is_call: prefer non-deref, non-method, non-binop
4. Prefer is_block over is_hash (`{ }` is a block, not a hash)
5. Prefer is_vardecl over non-vardecl (`my` is a declaration keyword)

Each preference returns the winning value (not a new value), so
FilterComposite can detect which side won via identity comparison.

#### 4.2.5 SemanticAction — IR Construction

Values are Context objects from a comonad (extract/extend/duplicate)
that builds the output IR tree. SemanticAction does not disambiguate —
it consumes the disambiguated parse to construct output.

**On scan:** create a leaf Context with the matched text as focus.
Hash-consed: same text → same Context object.

**On complete:** apply the rule's semantic action via `extend`. The
action is a function that receives the children Contexts and produces
an IR node (Constructor, Constant, etc.). SemanticAction reads type
annotations from TypeInference (threaded via FilterComposite's TI→SA
protocol) to inform IR construction.

**On multiply:** combine Contexts via the comonad multiply (sequence
composition). The left Context becomes the parent, the right becomes a
child.

**On add:** identity-based deduplication. If two Contexts have the same
refaddr (same derivation), return one. Otherwise, return both for
FilterComposite to resolve.

### 4.3 FilterComposite — Ordered Priority Composition

FilterComposite wraps the five semirings into a single composite value
(a 5-element tuple). It delegates each operation to all five components
and applies zero propagation: if ANY component returns zero, the entire
tuple is zero.

**The `add` protocol (disambiguation):**

When two composite values merge, FilterComposite resolves the ambiguity
using ordered priority:

1. Check each component semiring in order:
   Boolean → Precedence → TypeInference → Structural → SemanticAction

2. For each component, call its `add(left_i, right_i)` and inspect the
   result. If the result is identity-equal to `left_i` but not
   `right_i`, this semiring prefers left. Vice versa for right.

3. The *first* semiring to express a preference wins. Later semirings
   are not consulted.

4. If no semiring expresses a preference, deterministic tie-break picks
   left.

This is a first-wins ordered filter. Earlier semirings have higher
priority: Boolean can override everything, Precedence overrides
TypeInference, and so on. In practice, Boolean never disambiguates
(it accepts all valid paths), so Precedence is the first effective
disambiguator.

**TI→SA threading:**

FilterComposite threads the TypeInference result to SemanticAction
during `on_complete`. After the TypeInference component (index 2)
completes, its result is passed to SemanticAction (index 4) via
`set_type_context`. This allows SemanticAction's rule actions to read
type annotations (e.g., return type, argument types) when constructing
IR nodes.

---

*Sections 5-12 and Appendices continue in subsequent commits.*

---

## 5. LR(0) DFA Construction

The DFA eliminates per-position prediction, terminal discovery, and
completion search by precomputing these as properties of grammar states.
This section describes how to build the DFA from a grammar.

### 5.1 Core Items

A *core item* is a pair `(rule_name, alt_index, dot)` — an Earley item
without its origin. Core items represent grammar positions: "we are
inside rule R, alternative A, at position D in the right-hand side."

The set of all core items for a grammar is finite and small. For a
grammar with R rules whose alternatives have average length L, there
are approximately `R * (L + 1)` core items. A 65-rule Perl grammar
with average RHS length 3-4 yields roughly 300-400 core items.

Each core item receives a unique integer ID (the *core_id*). A
*core item index* maps between the triple and the integer:

```
register(rule_name, alt_index, dot) -> core_id
id_for(rule_name, alt_index, dot)   -> core_id or undef
item_for(core_id)                   -> {rule_name, alt_index, dot}
advance(core_id)                    -> next core_id (dot + 1)
```

The index also precomputes per-core_id properties:

```
is_complete(core_id)   -> bool     (dot at end of alternative)
symbol_after(core_id)  -> Symbol   (the symbol after the dot, or undef)
rule_name_for(core_id) -> string   (O(1) array lookup)
alt_idx_for(core_id)   -> int      (O(1) array lookup)
```

These are populated once at grammar construction time and never change.

### 5.2 DFA States

A *DFA state* is a set of core_ids representing grammar positions that
are active simultaneously. Two DFA states are equal when they contain
the same set of core_ids.

The standard LR(0) construction builds DFA states through two
operations:

**Closure.** Given a set of core_ids (the *kernel*), add all core_ids
reachable through prediction. If core_id C has a reference to
nonterminal N after its dot, add all core_ids for N's alternatives at
dot position 0. Repeat transitively until no new core_ids are added.

```
closure(kernel):
  result = kernel
  worklist = kernel
  while worklist not empty:
    core_id = pop worklist
    if not is_complete(core_id):
      sym = symbol_after(core_id)
      if sym is a reference to nonterminal N:
        for each alternative A of N:
          new_id = id_for(N, A, 0)
          if new_id not in result:
            add new_id to result
            add new_id to worklist
  return result
```

The closure also handles nullable symbols: if the symbol after the dot
is nullable (can derive the empty string), advance past it and include
the advanced core_id in the closure. This is the Aycock-Horspool
nullable optimization.

**Goto.** Given a DFA state S and a symbol X (terminal or nonterminal),
compute the set of core_ids that result from advancing all items in S
that have X after their dot:

```
goto(S, X):
  kernel = {}
  for core_id in S:
    if symbol_after(core_id) == X:
      add advance(core_id) to kernel
  return closure(kernel)
```

The DFA is constructed by starting from the closure of the start rule's
items and repeatedly computing goto for all symbols:

```
build_dfa(grammar):
  start_kernel = { id_for(start_rule, A, 0) for each alt A }
  state_0 = closure(start_kernel)
  register state_0
  worklist = [state_0]

  while worklist not empty:
    state = pop worklist
    for each symbol X expected by items in state:
      target = goto(state, X)
      if target not already registered:
        register target
        add target to worklist
      record transition: state --X--> target
```

Each DFA state is registered in a hash table keyed by its sorted
core_id set. The number of DFA states is bounded by the grammar — it
does not depend on the input.

### 5.3 State Properties

Each DFA state has precomputed properties that the parse loop uses:

**Terminal map.** For each terminal pattern expected by items in this
state, which core_ids expect it:

```
terminal_map: { pattern_string -> [core_id, ...] }
```

At parse time, the parser tries each terminal in the map once per
position (not once per item). If the terminal matches, the matching
core_ids are known immediately from the map.

**Completion map.** For each nonterminal that items in this state are
waiting for, which core_ids are waiting:

```
completion_map: { nonterminal_name -> [core_id, ...] }
```

When a rule completes at a position whose origin has this DFA state,
the parser looks up the completion map instead of searching the chart.
The map narrows the search from "all items in the grammar waiting for
this nonterminal" to "only items active in this state."

**Prediction set.** The nonterminals predicted by this state (those
with references after the dot). This is implicit in the closure — the
nonkernel items (dot=0) are the predictions.

**Complete items.** Which core_ids in this state are complete (dot at
end). These trigger the completion step.

**Goto table.** For each symbol X, which DFA state results:

```
goto_table: { symbol -> target_state_id }
```

This replaces the `advance` + chart-scan pattern. When a scan or
completion advances past symbol X, the next state is
`goto_table[current_state][X]` — a single table lookup.

### 5.4 Worked Example: DFA for Arithmetic

Grammar:
```
Expr   ::= Expr '+' Term    (alt 0)
          | Term             (alt 1)
Term   ::= 'number'         (alt 0)
```

Core items (8 total):
```
ID 0: [Expr, 0, 0]  Expr -> . Expr '+' Term
ID 1: [Expr, 0, 1]  Expr -> Expr . '+' Term
ID 2: [Expr, 0, 2]  Expr -> Expr '+' . Term
ID 3: [Expr, 0, 3]  Expr -> Expr '+' Term .      (complete)
ID 4: [Expr, 1, 0]  Expr -> . Term
ID 5: [Expr, 1, 1]  Expr -> Term .                (complete)
ID 6: [Term, 0, 0]  Term -> . 'number'
ID 7: [Term, 0, 1]  Term -> 'number' .            (complete)
```

**State 0** (initial): closure({0, 4}) = {0, 4, 6}
- Terminal map: `{'number' -> [6]}`
- Completion map: `{}`  (no items waiting for a nonterminal here
  besides predicted ones)
- Goto: `Expr -> State 1`, `Term -> State 2`, `'number' -> State 3`

**State 1**: closure({1}) = {1}
- Terminal map: `{'+' -> [1]}`
- Completion map: `{}`
- Complete items: `{}` (but Expr alt 1 completes via State 2)
- Goto: `'+' -> State 4`

**State 2**: closure({5}) = {5}
- Complete items: `{5}` (Expr -> Term .)
- Terminal map: `{}`
- Completion map: `{}`

**State 3**: closure({7}) = {7}
- Complete items: `{7}` (Term -> 'number' .)
- Terminal map: `{}`
- Completion map: `{}`

**State 4**: closure({2}) = {2, 6}
- Terminal map: `{'number' -> [6]}`
- Completion map: `{Term -> [2]}`
- Goto: `Term -> State 5`, `'number' -> State 3`

**State 5**: closure({3}) = {3}
- Complete items: `{3}` (Expr -> Expr '+' Term .)
- Terminal map: `{}`
- Completion map: `{}`

Six states for a 3-rule grammar. The parse loop will navigate these
states using the goto table, never computing predictions or searching
for waiting items.

### 5.5 Extending to the Perl Grammar

A 65-rule Perl grammar produces approximately 80-120 DFA states. The
state count depends on how many distinct combinations of active rules
the grammar produces. In practice:

- Statement-level states (expecting Statement, Declaration, Expression)
  are shared across all positions where a statement can begin.
- Expression states (inside a BinaryExpression, after an operator)
  recur at every infix position.
- Declaration states (inside a MethodDecl, after a field attribute) are
  specific to class bodies.

The DFA state count is independent of input size. A 10-line file and a
10,000-line file navigate the same DFA states — only the number of
transitions differs.

---

## 6. Distance Factoring

Distance factoring separates the grammar-structural part of an Earley
set from the input-specific part. This section describes the
representation and its implications for set reuse.

### 6.1 The Observation

Consider two positions in a source file:

```
Position 100:  my $x = 1;
Position 200:  my $y = 2;
```

Both positions occur at the start of a statement. The Earley sets at
both positions contain the same active rules: Statement alternatives,
Expression alternatives, Declaration alternatives. The *core* of both
sets is identical — the same DFA state.

What differs is the *origin* of each item. At position 100, the
StatementList item originated at position 0 (start of program). At
position 200, it originated at position 100 (after the first
statement). The origins differ, but the structure is the same.

Standard Earley stores each set as a collection of `(core_id, origin)`
pairs. Two sets with identical cores but different origins are treated
as completely different — predictions recomputed, completions
rediscovered, terminal patterns retried.

Distance factoring stores each set as:

```
Set = (core, distances)
```

Where `core` is the DFA state (shared across positions) and `distances`
is a per-item distance from the current position to the origin. For an
item at position 200 with origin 100, the distance is 100. For an item
at position 100 with origin 0, the distance is also 100.

If two positions have the same core AND the same distance vector, they
are structurally identical — the parse will proceed identically from
both positions. Only the semiring values (the parse-tree content)
differ.

### 6.2 Relative Distances

An item's origin is stored as a *relative distance* from the current
position:

```
rel_dist = current_position - origin
```

An item at position 500 with origin 495 has `rel_dist = 5`. The same
item at position 1000 with origin 995 also has `rel_dist = 5`.

Relative distances are small integers. Profiling of real Perl source
files shows:
- 67% of distances are 0-1
- 82% are 0-7
- The maximum distance is bounded by the longest statement span

Small integers index efficiently into arrays. The chart representation
uses:

```
chart[position][core_id][rel_dist] = value
```

This replaces hash-based origin indexing with direct array access. No
hash computation, no key comparison, no collision handling.

### 6.3 Core and Distance Hashing

Both cores and distance vectors are hash-consed for deduplication:

**Core hashing.** A core is identified by its sorted list of active
core_ids. The hash key is the comma-joined string of these integers.
The core registry maps this key to a unique core_id integer.

```
core_key = join(",", sort @active_core_ids)
core_id  = core_registry{core_key} // assign_new_id()
```

**Distance vector hashing.** A distance vector is the set of
`(core_id, rel_dist)` pairs at a position. The hash key is the
semicolon-joined string of these pairs.

```
dist_key = join(";", sort map { "$cid:$rd" } @pairs)
set_key  = "$core_id:$dist_key"
```

Two positions with the same `set_key` are structurally identical.

### 6.4 Lifetime Management

Data structures have two lifetimes:

**Grammar-lifetime** (persists across file parses):
- DFA states and transitions
- Core item index
- Terminal maps, completion maps, goto tables
- Operation tables (Section 7)

**Parse-lifetime** (cleared between files):
- Chart values
- Distance vectors
- Completed-item indexes
- Scan result cache

Grammar-lifetime data is computed once for a given grammar and reused
across all source files. Parse-lifetime data is specific to one input.

### 6.5 Garbage Collection

Two GC mechanisms reclaim chart memory during a parse:

**Safe-set GC** (Aycock Chapter 6). A chart position is *safe* when
no future completion can reference it. Properties:
1. At least one complete item exists
2. No non-complete item's last-consumed symbol conflicts with a
   complete item's last symbol
3. No complete item resulted from an empty rule

When a safe position is found, all chart data between the previous safe
position and this one can be freed. For statement-boundary grammars,
safe positions occur at every semicolon.

**Epoch GC** (statement-boundary sweeping). When a StatementItem rule
completes, the parser receives a callback with the statement's origin
and end positions. All completed items strictly inside this range can
be nulled — their results have already propagated to the boundary.

Both GC mechanisms operate on the `chart[pos][core_id][rel_dist]` array
by setting entries to `undef`. Compact positions (all entries undef) are
replaced with empty arrays.

---

## 7. The Operation Table

The operation table is the central data structure of the DFA-factored
parser. Each DFA state has a table that encodes every operation the
parser will perform when processing items in that state. The parse loop
becomes a table interpreter: read an entry, execute it against
per-position values.

### 7.1 Table Structure

An operation table is an array of *entries*. Each entry describes one
operation:

```
Entry = {
  op_type:       'complete' | 'scan' | 'predict' | 'skip_optional'
  core_id:       the core item this entry applies to
  rule_name:     the rule name (precomputed from core_id)
  alt_idx:       the alternative index (precomputed from core_id)

  # For 'complete' entries:
  target_state:  DFA state after advancing past the completed nonterminal
  waiters:       [core_ids in this state waiting for this nonterminal]

  # For 'scan' entries:
  pattern:       the terminal regex pattern to match
  target_state:  DFA state after advancing past the terminal
  compiled_re:   precompiled regex object

  # For 'predict' entries:
  predicted_state: the DFA state containing the predicted items

  # Semiring columns (one per semiring):
  boolean_op:    'identity' | 'check_zero'
  prec_op:       'identity' | 'reset' | 'assign_level' | 'pass_through'
  prec_level:    integer (for 'assign_level')
  prec_assoc:    'left' | 'right' | 'nonassoc' (for 'assign_level')
  type_op:       'identity' | 'check_signature' | 'assign_type' | 'reject_keyword'
  type_result:   Type bitset (for 'assign_type')
  type_sig:      {left: Type, right: Type, result: Type} (for 'check_signature')
  struct_op:     'identity' | 'tag'
  struct_bits:   integer bitfield (for 'tag')
  sa_action:     reference to semantic action function (for 'complete')
}
```

### 7.2 Building the Table

The operation table for a DFA state is built once at grammar
construction time (or lazily on first encounter during parsing). For
each core_id in the state:

1. If `is_complete(core_id)`: create a `'complete'` entry. Look up the
   rule_name. Consult each semiring's `on_complete` behavior for this
   rule to fill the semiring columns. Look up the completion map to
   find waiters. Look up the goto table for the target state.

2. If `symbol_after(core_id)` is a terminal: create a `'scan'` entry.
   Record the pattern and compiled regex. Look up the goto table for
   the target state. Fill semiring columns from each semiring's
   `on_scan` behavior for this rule.

3. If `symbol_after(core_id)` is a nonterminal reference: create a
   `'predict'` entry. The predicted state is `goto(this_state, N)`.

4. If the nonterminal is nullable or `?`-quantified: create a
   `'skip_optional'` entry. The target is `advance(core_id)`.

### 7.3 Semiring Column Compilation

Each semiring contributes a column to the operation table. The column
encodes what that semiring would do for this entry, expressed as data
rather than method calls:

**Boolean column.** Always `'identity'` for non-zero items. The
Boolean semiring's `on_complete` and `on_scan` are transparent —
they return their input unchanged. The only meaningful operation is
`is_zero`, which is checked at the composite level.

**Precedence column.** Determined by the rule_name:
- `ParenExpr`, `ArrayConstructor`, `HashConstructor` → `'reset'`
  (return `one()`)
- `PostfixExpression`, `UnaryExpression` → `'assign_level'` with the
  expression type's level
- `BinaryOp`, `AssignOp` → `'pass_through'` (value carries operator
  info from scan)
- `BinaryExpression`, `Expression` → `'pass_through'`
- `Subscript` → conditional (pass through if level >= 100, else reset)
- Other rules → `'reset'`

**TypeInference column.** Determined by the rule_name and action
dispatch:
- Rules with type actions → `'check_signature'` with the operator/
  builtin signature
- Boundary rules → `'identity'` (propagate child type)
- Keyword-sensitive rules → `'reject_keyword'` with the keyword table

**Structural column.** Determined by the rule_name:
- `Block` → `'tag'` with `STRUCT_IS_BLOCK`
- `CallExpression` → `'tag'` with `STRUCT_IS_CALL`
- `HashConstructor` → `'tag'` with `STRUCT_IS_HASH`
- etc.

**SemanticAction column.** A reference to the rule's semantic action
function (a closure or function pointer). This is the only column that
cannot be fully reduced to a simple data value — the action function
builds IR nodes and requires the actual parse values as input.

### 7.4 Table Execution

Executing an operation table entry against per-position values:

```
execute_complete(entry, completed_value, chart, pos):
  # Apply semiring on_complete operations
  if entry.boolean_op == 'check_zero':
    return if is_zero(completed_value[0])

  prec_value = apply_prec_op(entry, completed_value[1])
  type_value = apply_type_op(entry, completed_value[2])
  struct_value = apply_struct_op(entry, completed_value[3])
  sa_value = apply_sa_action(entry, completed_value[4])

  if is_zero(prec_value) or is_zero(type_value):
    return  # path killed by disambiguation

  result = [true, prec_value, type_value, struct_value, sa_value]

  # Advance waiting items (from entry.waiters)
  for waiter_core_id in entry.waiters:
    for each (waiter_value, waiter_origin) at chart[origin][waiter_core_id]:
      combined = composite_multiply(waiter_value, result)
      target_core_id = advance(waiter_core_id)
      add_to_chart(pos, target_core_id, waiter_origin, combined)
```

The key difference from standard Earley: the entry knows which
semiring operations to apply (data) and which items to advance
(precomputed). The loop applies values to a fixed structure rather than
discovering the structure at runtime.

### 7.5 Worked Example: Operation Table for State 4

From the arithmetic DFA (Section 5.4), State 4 contains:
```
{2: Expr -> Expr '+' . Term,  6: Term -> . 'number'}
```

Operation table:
```
Entry 0: {
  op_type: 'scan',
  core_id: 6,  (Term -> . 'number')
  pattern: '\d+',
  target_state: 3,  (State 3 = {7: Term -> 'number' .})
  boolean_op: 'identity',
  prec_op: 'identity',
  type_op: 'assign_type',
  type_result: Int,
  struct_op: 'identity',
}

Entry 1: {
  op_type: 'complete',  (handled when Term completes at this origin)
  core_id: 2,  (Expr -> Expr '+' . Term)
  waiters: [2],  (core_id 2 is waiting for Term)
  target_state: 5,  (State 5 = {3: Expr -> Expr '+' Term .})
  boolean_op: 'identity',
  prec_op: 'pass_through',
  type_op: 'check_signature',
  type_sig: {left: Num, right: Num, result: Num},
  struct_op: 'identity',
}
```

When the parser is in State 4 at position 2 (after `+` in `2+3`):
1. Execute Entry 0: try matching `\d+`. It matches `3` (pos 2..3).
   Create a scan result with type Int. Advance to State 3.
2. When Term completes at State 3 (Entry 1 fires at the origin):
   multiply the waiting Expr value with the Term value. Check the
   type signature: left operand from Expr is Num (from scanning `2`),
   right operand from Term is Int (which satisfies Num). Result type
   is Num. Advance to State 5.

---

## 8. The Parse Loop

The parse loop is the runtime algorithm. It processes input positions
sequentially, executing operation table entries against per-position
values. The DFA provides all structural decisions; the loop only
performs value work.

### 8.1 Data Structures

**Chart.** `chart[pos][core_id][rel_dist] = value`
- `pos`: input position (0 to N)
- `core_id`: integer from core item index
- `rel_dist`: `pos - origin` (relative distance)
- `value`: 5-element semiring tuple

**DFA state per position.** `state_at[pos] = dfa_state_id`
- Tracked from goto transitions, not discovered by scanning the chart.

**Completed index.** `completed_at[rule_name][origin][pos] = [(core_id, origin), ...]`
- Secondary index for completion lookups.

**Leo items.** `leo_items[rule_name][origin] = {top_core_id, top_origin, value, wait_core_id, wait_origin}`
- Side table for right-recursive chain shortcutting.

### 8.2 The Algorithm

```
parse(input, grammar, dfa):
  N = length(input)
  chart = array of (N+1) empty slots
  state_at = array of (N+1) slots

  # Initialize: place start rule items at position 0
  start_state = dfa.state(0)
  for each core_id in start_state.core_ids:
    chart[0][core_id][0] = semiring.one()
  state_at[0] = start_state.id

  # Pre-scan: for each terminal pattern in the grammar,
  # find all positions where it matches (optional optimization)

  for pos = 0 to N:
    state = dfa.state(state_at[pos])

    # Phase 1: Process completions
    for each complete entry in state.operation_table:
      core_id = entry.core_id
      rule_name = entry.rule_name
      for each (value, origin) at chart[pos][core_id]:
        completed_value = execute_on_complete(entry, value, pos, origin)
        if is_zero(completed_value): skip

        # Record completion
        completed_at[rule_name][origin][pos].push(core_id, origin)

        # Find waiters at the origin position
        origin_state = dfa.state(state_at[origin])
        waiters = origin_state.completion_map[rule_name]
        for each waiter_core_id in waiters:
          for each (waiter_value, waiter_origin) at chart[origin][waiter_core_id]:
            combined = semiring.multiply(waiter_value, completed_value)
            if is_zero(combined): skip
            target_core_id = advance(waiter_core_id)
            merge_into_chart(pos, target_core_id, waiter_origin, combined)

    # Phase 2: Process scans (only if not at end of input)
    if pos < N:
      for each scan entry in state.operation_table:
        pattern = entry.pattern
        end_pos = try_match(input, pos, entry.compiled_re)
        if end_pos is undef: skip

        matched_text = substr(input, pos, end_pos - pos)

        # Apply should_scan gate
        for each (value, origin) at chart[pos][entry.core_id]:
          if not should_scan(entry, value, matched_text): skip
          scan_value = execute_on_scan(entry, value, pos, matched_text)
          if is_zero(scan_value): skip
          target_core_id = advance(entry.core_id)
          merge_into_chart(end_pos, target_core_id, origin, scan_value)

        # Record the target DFA state at end_pos
        state_at[end_pos] = entry.target_state

    # Phase 3: GC (safe-set and epoch)
    perform_gc(chart, pos)

  # Check for completed start rule at position N
  start_rule_name = grammar.start_rule.name
  for each alt of start rule:
    end_core_id = id_for(start_rule_name, alt, alt.length)
    value = chart[N][end_core_id][N]  # rel_dist = N - 0 = N
    if defined(value) and not is_zero(value):
      return value

  return undef  # parse failure
```

### 8.3 Merge Protocol

When adding a value to a chart cell that already contains a value:

```
merge_into_chart(pos, core_id, origin, new_value):
  rel_dist = pos - origin
  existing = chart[pos][core_id][rel_dist]

  if not defined(existing):
    chart[pos][core_id][rel_dist] = new_value
    return  # new item — add to processing queue

  # Existing item — merge via semiring add
  merged = semiring.add(existing, new_value)
  chart[pos][core_id][rel_dist] = merged
```

The semiring `add` resolves ambiguity: Precedence picks the better
operator grouping, Structural picks block over hash, TypeInference
provides type information for the choice.

### 8.4 DFA State Tracking

The critical difference from the current Earley implementation: DFA
state tracking replaces chart scanning.

In standard Earley, the parser discovers which rules are active by
examining the chart. In the DFA-factored parser, the state follows from
transitions:

- **Initial state**: the DFA's start state.
- **After a scan**: the target state is `scan_entry.target_state`.
- **After a completion**: the target state for the advanced item is
  determined by `goto(origin_state, completed_nonterminal)`.

Multiple scans or completions at the same position may produce items
belonging to different DFA states. The `state_at[pos]` tracks the
primary state (from scanning). Completion-produced items are looked up
via the goto table on the origin's state, not by discovering a new
DFA state.

This eliminates the `_discover_core_set` chart scan that currently
runs at every position — a significant source of overhead.

### 8.5 Leo Optimization

The Leo optimization handles right-recursive rules in O(1) per
recursive step instead of O(n). When a completion is *deterministic*
(exactly one waiting item, at the penultimate position), the parser
creates a Leo item that represents the entire chain.

Leo items store:
```
{
  top_core_id:  the waiting item at the top of the chain
  top_origin:   the origin of the top-of-chain item
  value:        the accumulated multiply product
  wait_core_id: the immediate waiting item (for dedup)
  wait_origin:  the immediate waiting item's origin
}
```

Leo items use absolute origins (not relative distances) because they
span arbitrary distances across the chain.

When a completion finds a Leo item for its rule at the origin, it
resolves the entire chain in one step: multiply the Leo chain's
accumulated value with the completed value, then advance the top-of-
chain item.

### 8.6 Interaction with Operation Tables

The parse loop interleaves DFA-driven control flow with per-position
value work:

1. The DFA state determines WHICH entries to execute (control flow).
2. The operation table determines WHAT each entry does to the semiring
   values (partially applied from grammar analysis).
3. The per-position chart provides the VALUES to operate on.

The DFA state and operation table are grammar-lifetime data. The chart
values are parse-lifetime data. The parse loop connects them.

---

## 9. Error Detection, Diagnostics, and Recovery

### 9.1 Error Detection

A parse fails when no complete start-rule item exists at position N.
The parser detects this by checking `chart[N]` for the start rule.

The parser tracks the *last active position*: the furthest input
position where any item had a defined value. If the last active
position is less than N, the input was not fully consumed. The
difference between last active position and N indicates where parsing
stalled.

### 9.2 Diagnostics

At the last active position, the DFA state's terminal map provides the
set of *expected tokens*: the terminals that could have allowed parsing
to continue. This set is precise because the DFA state encodes exactly
which items are active.

The parser produces a Rust-style diagnostic:

```
error: parse failed at line 12, column 5
  --> lib/Foo.pm:12:5
   |
10 | method bar($self) {
11 |     my $x = $obj->
12 |     frobnicate();
   |     ^
   |
   = expected: identifier, '->', ';'
   = note: parsing stopped at 245 of 500 bytes
```

The expected token set comes from `state.terminal_map.keys()`. The
source context comes from the input text around the failure position.

### 9.3 Error Recovery

Error recovery allows the parser to continue past syntax errors,
producing partial parse results and additional diagnostics.

**Token skipping recovery.** When the parser detects failure at
position P:

1. Record the error and expected tokens at P.
2. Find the nearest *synchronization point*: a position after P where
   a token from the expected set matches. Synchronization tokens are
   typically statement terminators (`;`), block closers (`}`), or
   declaration keywords (`method`, `field`, `class`).
3. Skip input from P to the synchronization point.
4. Resume parsing from the synchronization point's DFA state.

**Recovery state selection.** The DFA state at the synchronization
point is determined by examining which DFA states could have reached
the synchronization token. In practice, statement-level recovery works
by:
1. Walking backward from the failure to find the most recent safe-set
   boundary (Aycock Chapter 6).
2. Using the DFA state at that boundary as the recovery starting point.
3. Scanning forward to the synchronization token.

**Multiple error reporting.** After recovery, parsing continues
normally. If additional errors are found, they are reported with the
same diagnostic format. The parser limits the number of reported errors
(typically 10-20) to avoid cascading noise.

**Partial result construction.** When SemanticAction encounters a
recovery point, it inserts an error placeholder node in the IR tree.
The placeholder records the skipped span and the recovery point. The
code generation pipeline can handle error nodes by emitting diagnostic
comments or skipping the affected statement.

---

## 10. Grammar Construction and BNF Bootstrap

### 10.1 Grammar Builder API

The grammar is an array of Rule objects. Each Rule has a name and a
list of alternatives. Each alternative is a list of Symbols.

**Symbol types:**
- `terminal(pattern)`: a regex pattern that matches input text
- `reference(name)`: a nonterminal referring to another rule by name
- `reference(name, quantifier)`: a quantified reference (`?`, `*`, `+`)

**Quantifier desugaring.** Quantifiers are syntactic sugar:
- `B?` (optional): creates a skip path that advances past B without
  matching, calling `on_skip_optional` to create a placeholder value.
- `B*` (zero-or-more): desugars to a helper rule `B_star ::= B_star B | epsilon`
- `B+` (one-or-more): desugars to `B_plus ::= B_plus B | B`

**Grammar construction:**
```
grammar = [
  Rule("Expr", [
    [reference("Expr"), terminal("\\+"), reference("Term")],
    [reference("Term")],
  ]),
  Rule("Term", [
    [terminal("\\d+")],
  ]),
]
```

The first rule in the array is the start rule.

### 10.2 BNF Syntax

The grammar can also be specified in BNF notation:

```
Expr   ::= Expr '+' Term
          | Term

Term   ::= /\d+/
```

Rules are separated by blank lines. Alternatives within a rule are
separated by `|`. Terminals can be single-quoted strings (literal match)
or `/regex/` patterns. Nonterminal references are bare names. Comments
start with `#`.

### 10.3 The BNF Bootstrap

The parser can compile its own grammar format. The BNF meta-grammar
(a grammar that describes BNF syntax) is:

```
Grammar    ::= Rule+
Rule       ::= Identifier '::=' Alternatives
Alternatives ::= Sequence ('|' Sequence)*
Sequence   ::= Element+
Element    ::= Atom Quantifier?
Atom       ::= Identifier | InlineRegex | QuotedString
Quantifier ::= '?' | '*' | '+'
Identifier ::= /[A-Za-z_]\w*/
InlineRegex ::= /\/[^\/]+\//
```

The bootstrap path:

1. **Hand-write** a parser for the BNF meta-grammar (10 rules). This
   parser can be a simple recursive descent parser or a hand-coded
   Earley parser.

2. **Parse** the Perl subset grammar (65 rules) using the BNF parser.
   This produces a grammar object (array of Rules).

3. **Build** the DFA from the grammar object (Section 5).

4. **Parse** Perl source files using the DFA-factored parser.

The BNF parser itself can eventually be compiled through this pipeline
(self-hosting): parse the BNF meta-grammar with the BNF parser,
producing a grammar object that describes BNF, then build a
DFA-factored parser for BNF. This DFA-factored BNF parser replaces the
hand-written one.

---

## 11. Code Generation Pipeline

The parser produces a composite semiring value containing an IR tree
(from SemanticAction) annotated with type information (from
TypeInference). This section describes the pipeline from parse result
to compiled output.

### 11.1 The IR: Sea of Nodes

The IR uses a Sea of Nodes representation:

- **Data nodes**: Constant, BinaryOp, UnaryOp, Call, FieldAccess
- **Control nodes**: Start, Return, If, Region, Loop
- **Structure nodes**: Constructor (ClassDecl, MethodDecl, FieldDecl, etc.)

All nodes are immutable and hash-consed. Identical subexpressions share
the same node object.

### 11.2 Pipeline Stages

```
Source Text
    |
    v
[Parser + Semirings]  -->  Composite Value
    |                       [Boolean, Precedence, TypeInference,
    |                        Structural, SemanticAction]
    v
[Extract IR]          -->  SemanticAction Context tree
    |
    v
[Optimization]        -->  Struct promotion, constant folding
    |
    v
[Code Generation]     -->  .c source + .h header + .xs wrapper
    |
    v
[C Compiler]          -->  .o object files
    |
    v
[Linker]              -->  .so shared library
```

### 11.3 C Code Generation

The code generator (Target::C) translates IR nodes to C functions:

- Each class in the source becomes a C file with exported functions.
- Field access uses Perl's `ObjectFIELDS` API.
- Method dispatch uses either direct C calls (when the target class is
  known from type information) or `call_method` (generic dispatch).
- The DFA tables can be emitted as static C arrays, making the parser
  itself compilable to C.

### 11.4 XS Wrappers

Each generated C file gets a thin XS wrapper that:
- Registers the C functions as Perl methods (via BOOT block)
- Sets up field attributes (:param, :reader, :writer) using the
  Perl 5.42 class C API
- Handles ADJUST blocks as native XSUBs

The result is a shared library (`.so`) that Perl loads at runtime,
replacing the pure-Perl implementation with compiled C.

### 11.5 Type Information in Code Generation

TypeInference's output influences code generation:

- **Direct C calls**: when the type of an invocant is known (e.g.,
  `$semiring` is typed as `FilterComposite`), the code generator emits
  a direct C function call instead of `call_method`. This eliminates
  Perl method dispatch overhead.

- **Field access optimization**: when a `:reader` field is accessed on
  a known type, the code generator emits `ObjectFIELDS(SvRV(self))[idx]`
  instead of a method call — a single C array access.

- **Operator specialization**: when operand types are known, the code
  generator can emit specialized C code (e.g., `SvIV` for Int instead
  of the generic `SvNV` for Num).

---

## 12. Performance Analysis

### 12.1 Complexity

**Standard Earley**: O(n^3) worst case, O(n^2) unambiguous, O(n) LR(k).
The constant factors are dominated by item allocation, hash-based
membership testing, and redundant prediction.

**DFA-factored Earley**: Same asymptotic complexity, but with smaller
constant factors:

| Operation | Standard | DFA-factored |
|-----------|----------|-------------|
| Prediction | O(rules) per position | O(1) DFA state lookup |
| Membership | Hash lookup per item | Array index per core_id |
| Completion search | O(items at origin) | O(waiters in completion map) |
| Terminal matching | O(items * patterns) | O(patterns in terminal map) |
| Core set discovery | O(chart width) per position | DFA transition (O(1)) |

The DFA-factored parser eliminates the O(chart width) per-position
overhead for prediction, terminal discovery, and core set tracking.

### 12.2 Set Reuse Impact

For repetitive source code (common in real programs), set reuse avoids
redundant work:

- **Prediction reuse**: positions with the same DFA state share
  predictions. In a file with 100 statements, statement-start
  predictions are computed once and reused 99 times.

- **Completion map reuse**: the completion map for a DFA state is
  computed once. All positions in that state use the same map.

- **Terminal map reuse**: terminal matching patterns are tried once per
  DFA state per position, not once per item.

### 12.3 Memory

The DFA adds grammar-proportional memory:
- DFA states: O(grammar_size) states, each containing O(items) core_ids
- Operation tables: O(grammar_size) entries
- Terminal maps: O(terminals * states)
- Completion maps: O(nonterminals * states)

For a 65-rule grammar, this is kilobytes of static data. The chart
remains the dominant memory consumer at O(n * items * distances), where
n is the input length, items is the average chart width, and distances
is the average number of origins per item.

Distance factoring reduces chart memory by sharing core data across
positions. The sparse array representation (`chart[pos][core_id][rel_dist]`)
is memory-efficient because most items have small relative distances
(82% are 0-7).

### 12.4 Benchmark Methodology

To validate the DFA-factored parser's performance:

1. **Parse all source files** in the project through both the standard
   and DFA-factored parsers. Compare wall-clock time per file.

2. **Profile operation counts**: count predict, scan, complete, and
   merge operations per parse. The DFA-factored parser should show
   fewer operations (predictions reused, completions narrowed).

3. **Profile memory**: measure peak RSS during parsing. Distance
   factoring should reduce memory by sharing core data.

4. **Validate correctness**: the DFA-factored parser must produce
   identical IR output for all source files. Any difference indicates
   a bug.

---

## Appendix A: Example BNF Grammar

A simplified Perl subset grammar for worked examples (15 rules):

```
Program         ::= StatementList

StatementList   ::= Statement
                   | StatementList ';' Statement

Statement       ::= Expression
                   | VariableDeclaration
                   | IfStatement

VariableDeclaration ::= 'my' Variable '=' Expression

IfStatement     ::= 'if' '(' Expression ')' Block

Block           ::= '{' StatementList '}'

Expression      ::= PostfixExpression
                   | BinaryExpression
                   | AssignmentExpression

PostfixExpression ::= Atom
                    | PostfixExpression '->' MethodCall

BinaryExpression ::= Expression BinaryOp Expression

AssignmentExpression ::= Variable '=' Expression

MethodCall      ::= Identifier '(' ExpressionList? ')'

ExpressionList  ::= Expression
                   | ExpressionList ',' Expression

BinaryOp        ::= /[+\-*\/]/
                   | /\.\./
                   | /[<>]=?|[!=]=/

Atom            ::= Variable
                   | /\d+/
                   | /"[^"]*"/

Variable        ::= /\$[a-zA-Z_]\w*/
                   | /\@[a-zA-Z_]\w*/
                   | /\%[a-zA-Z_]\w*/

Identifier      ::= /[a-zA-Z_]\w*/
```

---

## Appendix B: Full Worked Trace

This appendix traces the complete parse of a 3-line Perl program through
all phases: DFA state transitions, distance factoring, and all five
semirings.

### Input

```perl
my $x = 2 + 3;
my $y = $x * 4;
```

### DFA States Encountered

Using the grammar from Appendix A:

**Position 0** (`m` of `my`): DFA State 0 (start state)
- Active items: Program -> . StatementList, StatementList -> . Statement, etc.
- Terminal map: `{'my' -> [...], /\$\w+/ -> [...], /\d+/ -> [...], ...}`

**Scan `my`** (pos 0..2): matches terminal `'my'`
- Advance to DFA State for VariableDeclaration
- TypeInference: keyword `my` confirmed as declaration, not identifier

**Scan `$x`** (pos 3..5): matches terminal `/\$[a-zA-Z_]\w*/`
- TypeInference: `{type: Scalar}` (from `$` sigil)

**Scan `=`** (pos 6..7): matches terminal `'='`
- Precedence: assignment operator, level 101, right-associative

**Scan `2`** (pos 8..9): matches terminal `/\d+/`
- TypeInference: `{type: Int}`

**Scan `+`** (pos 10..11): matches terminal `/[+\-*\/]/`
- Precedence: level 3, left-associative
- TypeInference: `{op_text: "+"}`

**Scan `3`** (pos 12..13): matches terminal `/\d+/`
- TypeInference: `{type: Int}`

**Complete BinaryExpression** (pos 8..13):
- Precedence: operator `+` at level 3 — valid nesting
- TypeInference: `+` signature is (Num, Num) -> Num.
  Left operand `2` is Int. TypeSatisfies(Int, Num) = true.
  Right operand `3` is Int. TypeSatisfies(Int, Num) = true.
  Result type: Num.
- Structural: `is_binop` tag set
- SemanticAction: builds BinaryExpr IR node with children [Constant(2), Constant(3)]

**Complete VariableDeclaration** (pos 0..13):
- TypeInference: `$x` now has inferred type Num (from the `+` expression)
- SemanticAction: builds VarDecl IR node

**Scan `;`** (pos 13..14): statement boundary
- Epoch GC fires: positions 0-13 eligible for sweeping

**Position 14**: DFA state returns to statement-start state (same as Position 0)
- Distance vector differs (StatementList origin is 0, not 14)
- But DFA state is the same — predictions reused from cache

The second statement (`my $y = $x * 4`) proceeds identically through the
same DFA states. TypeInference infers `$x` as Num (from the first
statement's declaration) and `$x * 4` as Num (from the `*` signature).

### Semiring Values at Key Points

| Position | Boolean | Precedence | TypeInference | Structural | SemanticAction |
|----------|---------|------------|---------------|------------|----------------|
| Scan `2` | true | one | {type: Int} | 0 | Context(focus:"2") |
| Scan `+` | true | {level:3, assoc:left, is_op:true} | {op_text:"+"} | 0 | Context(focus:"+") |
| Scan `3` | true | one | {type: Int} | 0 | Context(focus:"3") |
| Complete BinaryExpr | true | {level:3, assoc:left} | {type: Num} | is_binop | Context(BinaryExpr node) |
| Complete VarDecl | true | one | {type: Num} | is_vardecl | Context(VarDecl node) |

---

## Appendix C: Glossary

**Alternative.** One of the possible right-hand sides of a grammar
rule. A rule with three alternatives can match three different patterns.

**Chart.** The data structure holding all Earley items across all input
positions. Indexed by position, core_id, and relative distance.

**Completion.** The Earley operation that fires when a rule finishes
matching. Advances waiting items in the chart.

**Completion map.** Per DFA state: maps nonterminal names to the
core_ids waiting for that nonterminal. Precomputed from the state's
core items.

**Composite semiring.** A semiring that wraps multiple component
semirings, delegating operations to each and composing their results.

**Core.** The set of active core_ids at a chart position, independent
of origins or values. Corresponds to a DFA state.

**Core_id.** A small integer identifying a (rule_name, alt_index, dot)
triple. Assigned by the core item index.

**DFA state.** A set of core items computed by LR(0) closure. Each
state has precomputed terminal maps, completion maps, and goto
transitions.

**Distance factoring.** Separating an Earley set into (core, distances)
so that positions with the same core share structural work.

**Earley item.** A tuple of (rule, alternative, dot position, origin)
representing a partially-matched rule at a parse position.

**FilterComposite.** The composite semiring that orchestrates five
component semirings with ordered priority disambiguation.

**Goto table.** Per DFA state: maps symbols to target DFA states.
Precomputed from LR(0) construction.

**Leo optimization.** Right-recursive completion shortcutting. Reduces
O(n) per-step completion chains to O(1) by accumulating the chain value
in a side table.

**Nonterminal.** A grammar symbol that refers to a rule by name (a
reference). Contrast with terminal.

**Operation table.** Per DFA state: an array of entries describing
every operation the parser performs in that state, with precomputed
semiring columns.

**Origin.** The input position where an Earley item began matching.
Stored as a relative distance in the chart.

**Prediction.** The Earley operation that adds items for rules that
might match at the current position. In the DFA-factored parser,
predictions are implicit in the DFA state (closure includes all
predicted items).

**Relative distance.** `current_position - origin`. Small integers
suitable for array indexing.

**Rule.** A grammar rule with a name and one or more alternatives.

**Safe set.** A chart position where all items have completed and no
future completion can reference earlier positions. Safe for GC.

**Scan.** The Earley operation that matches a terminal pattern against
input text and advances the dot.

**Semiring.** An algebraic structure providing multiply (sequence), add
(merge), one (identity), and zero (dead) operations for the parser.

**Set reuse.** Reusing precomputed structural work when two positions
have the same DFA state. Predictions, terminal maps, and completion
maps are shared.

**Terminal.** A grammar symbol that matches input text via a regex
pattern. Contrast with nonterminal.

**Terminal map.** Per DFA state: maps terminal patterns to the core_ids
expecting that pattern. Enables once-per-pattern matching instead of
once-per-item.

**TypeSatisfies.** The subtype check: can a value of `actual` type
satisfy a `required` type? Accounts for subtyping, polymorphic
containers, and unknown types.
