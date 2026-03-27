# A DFA-Factored Earley Parser with Composite Semiring Disambiguation

**A design for parsing ambiguous grammars efficiently through precomputed
state machines, distance-factored chart representation, and type-directed
disambiguation.**

**Version**: 0.4 (Draft)
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
7. [The Parse Loop](#7-the-parse-loop)
8. [Error Detection, Diagnostics, and Recovery](#8-error-detection-diagnostics-and-recovery)
9. [Grammar Construction and BNF Bootstrap](#9-grammar-construction-and-bnf-bootstrap)
10. [Code Generation Pipeline](#10-code-generation-pipeline)
11. [Performance Analysis](#11-performance-analysis)

Appendices:
- [A: Example BNF Grammar](#appendix-a-example-bnf-grammar)
- [B: Full Worked Trace](#appendix-b-full-worked-trace)
- [C: Glossary](#appendix-c-glossary)
- [D: Operation Table Design (Future Optimization)](#appendix-d-operation-table-design-future-optimization)

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
- **Sections 5-7**: The DFA construction, distance factoring, and the
  parse loop. These sections specify the implementation. The parse loop
  retains Earley's agenda-driven structure (proven correct) while the
  DFA and distance factoring reduce its per-item overhead.
- **Section 8**: Error handling — detection, diagnostics, and recovery.
- **Section 9**: Grammar construction and the BNF bootstrap path.
- **Section 10**: The code generation pipeline from parse result to
  compiled C output.
- **Section 11**: Performance analysis and complexity bounds.
- **Appendix D**: A speculative future optimization — replacing the
  agenda loop with precomputed operation tables per DFA state.

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

**Operational summary for implementers.** The composite value at every
chart cell is a 5-element tuple `[Boolean, Precedence, TypeInference,
Structural, SemanticAction]`. Every semiring operation (`multiply`,
`add`, `on_scan`, `on_complete`) is delegated to all five components.
If ANY component returns zero, the entire tuple is zero (the parse path
dies). On `add` (merge), components are consulted in priority order
(Boolean first, SemanticAction last); the first component to express a
preference determines the winner (Section 4.3). Semiring values are
per-item — they travel with the item through the chart, not cached per
DFA state, because values depend on the input (what was scanned) not
just the grammar structure (which rule is active).

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

**On add (merge):** prefer the alternative with more specific type
information. Between two valid alternatives, the one with fewer
`Unknown` tags and more concrete types wins. For example, if one
derivation types `$x` as `Int` and the other as `Unknown`, the `Int`
derivation is preferred — it provides tighter constraints for
downstream disambiguation and code generation. This parallels
Precedence's preference for the most constraining level:
TypeInference prefers the most constraining type.

When both alternatives have equally specific types, return both (as
an arrayref) for FilterComposite to pass to Structural. TypeInference
kills invalid paths via zero (hard reject through `TypeSatisfies`
failure) and ranks valid paths by type specificity (soft preference).

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

**Semiring value caching (hash-consing).** Semiring values are per-item
(not per-DFA-state) because they depend on what was scanned, not just
which rule is active. However, identical derivations produce identical
values. Hash-consing exploits this:

- **Precedence** values are hash-consed by `(valid, level, assoc,
  is_operator)`. The `_intern` function returns the canonical object
  for each 4-tuple. Identity comparison via `refaddr` is O(1).

- **TypeInference** Context objects are hash-consed by focus content
  and children refaddrs. Two derivations producing the same type tags
  share the same Context. Cache key is
  `"ext:$rule_name:$focus_key:$children_key"`.

- **SemanticAction** Context objects are hash-consed by scanned text
  (for leaves) and by rule + children (for completions). Same-text
  scans at different positions share the same leaf Context.

- **Structural** values are plain integers (bitfields). No caching
  needed — integer comparison is direct.

- **Boolean** values are `true` or a unique zero reference. No caching
  needed.

Hash-consing serves two purposes: it reduces memory (identical
derivations share one object) and it enables FilterComposite's
identity-based disambiguation (when `add()` returns a value that is
`refaddr`-equal to one input, FilterComposite knows which side won).

Cache lifetime: hash-cons caches are cleared between file parses via
`reset_cache()`. Within a parse, caches grow monotonically. For large
files, this is the primary source of memory growth — bounded by the
number of distinct derivation shapes, which is grammar-proportional
(not input-proportional) for repetitive source code.

---

*Sections 5-11 and Appendices continue below.*

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

**Core_id to state mapping.** Each core_id belongs to exactly one DFA
state. This mapping is precomputed at DFA construction time:

```
state_for_core: core_id -> state_id
```

This is the inverse of the state's core_id list. At parse time, when
the parser needs the DFA state properties for an item (e.g., to look
up the completion map at an origin position), it looks up
`state_for_core[core_id]` — an O(1) array access. No chart scanning
or hash-key computation is required to determine which DFA state a
position is in.

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

### 5.6 Runtime Representation and Invariants

This section consolidates the runtime data structures into concrete
definitions that an implementer can code directly.

**The runtime item.** At parse time, an item is NOT an object or
struct. It is an implicit triple of integers identifying a position in
the chart:

```
(core_id, origin, position)
```

- `core_id`: integer index into the core item table (Section 5.1).
  Encodes the rule, alternative, and dot position. From the core_id,
  all grammar context is recoverable in O(1):
  - `rule_name_for(core_id)` → which rule
  - `alt_idx_for(core_id)` → which alternative
  - `dot_for(core_id)` → dot position within the alternative
  - `is_complete(core_id)` → whether the dot is at the end
  - `symbol_after(core_id)` → the next expected symbol
  - `state_for_core(core_id)` → which DFA state this item belongs to
- `origin`: the input position where this item began matching. Stored
  as a relative distance in the chart: `rel_dist = position - origin`.
- `position`: the current input position (the chart index).

The chart stores the semiring value at the intersection of these three
coordinates:

```
chart[position][core_id][rel_dist] = semiring_value
```

There is no separate item struct. The chart IS the item storage. To
enumerate items at a position, iterate `chart[pos]` for defined
entries. To look up a specific item, index directly:
`chart[pos][core_id][pos - origin]`.

**The agenda.** The agenda is a list of `[core_id, origin]` pairs
waiting to be processed at the current position. Values are read from
the chart when the item is processed (not when it is enqueued), because
merges may update the value between enqueue and processing.

**Core invariant: DFA states partition core items by future.**

```
For all core_ids C1, C2 in the same DFA state S:
  closure({C1}) ∩ closure({C2}) ⊇ nonkernel(S)
```

All items in the same DFA state share the same prediction closure
(nonkernel items). This means: at any parse position, items in the
same DFA state expect the same set of nonterminals to be predicted
and the same set of terminals to be scanned. Their *pasts* differ
(different rules, different dot positions, different origins) but
their *futures* — what they collectively predict and scan — are
identical.

More precisely, a DFA state is the epsilon-closure of a kernel set.
The kernel items (dot > 0) represent different grammar positions
arrived at by different paths. The nonkernel items (dot = 0) are
the predictions shared by all kernel items. The terminal map and
completion map are properties of the ENTIRE state (kernel +
nonkernel), not of individual items.

This invariant guarantees:

1. **Prediction correctness.** Adding prediction items for a DFA state
   is equivalent to adding them for each kernel item individually.
   No predictions are missed or spuriously added.

2. **Terminal map correctness.** The terminal map includes all patterns
   expected by any item in the state. No terminal match is missed.

3. **Completion map correctness.** The completion map includes all
   core_ids in the state that wait for each nonterminal. When a
   nonterminal completes, checking the completion map finds all
   relevant waiters.

**Diagnostic mapping.** Every core_id maps back to human-readable
grammar positions via the core item index:

```
core_id 42 → item_for(42) = {rule: "BinaryExpression", alt: 0, dot: 2}
           → "BinaryExpression -> Expression BinaryOp . Expression"
```

For logging and error diagnostics, the parser can reconstruct the full
grammar context of any chart entry:

```
format_item(core_id, origin, pos):
  info = item_for(core_id)
  rule = grammar.rule_for(info.rule_name)
  alt = rule.alternatives[info.alt_idx]
  lhs = info.rule_name
  rhs = format_rhs_with_dot(alt, info.dot)
  return "[{lhs} -> {rhs}] @ {origin} (pos {pos})"
```

This mapping is O(1) per item — it reads precomputed arrays. The DFA
does not obscure grammar positions; it indexes them by integer.

**Testable invariant assertions.** The DFA correctness invariant can
be verified programmatically after DFA construction:

```
verify_dfa_invariants(dfa, core_index):
  for each state S in dfa.states:
    # 1. Every core_id in S maps back to S
    for each core_id in S.core_ids:
      assert state_for_core[core_id] == S.id

    # 2. Nonkernel items are the prediction closure of kernel items
    kernel = [c for c in S.core_ids if dot_for(c) > 0 or c is start item]
    expected_nonkernel = epsilon_closure(kernel) - kernel
    actual_nonkernel = [c for c in S.core_ids if dot_for(c) == 0]
    assert set(actual_nonkernel) == set(expected_nonkernel)

    # 3. Terminal map covers all terminal-expecting items
    for each core_id in S.core_ids:
      sym = symbol_after(core_id)
      if sym is terminal:
        assert sym.pattern in S.terminal_map
        assert core_id in S.terminal_map[sym.pattern]

    # 4. Completion map covers all nonterminal-waiting items
    for each core_id in S.core_ids:
      sym = symbol_after(core_id)
      if sym is nonterminal reference:
        assert sym.name in S.completion_map
        assert core_id in S.completion_map[sym.name]

    # 5. Goto transitions are consistent
    for each (symbol, target_state_id) in S.goto_table:
      target = dfa.state(target_state_id)
      advanced = [advance(c) for c in S.core_ids
                  if symbol_after(c) == symbol]
      for each a in advanced:
        assert a in target.core_ids
```

These assertions run once after DFA construction (not during parsing)
and catch any inconsistency between the DFA tables and the core item
index. An implementation should run them in the test suite.

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

### 6.3 State Identity and Distance Hashing

**Core identity at construction time.** Each DFA state receives a
unique integer ID during DFA construction (Section 5.2). At parse
time, the DFA state for any item is known via `state_for_core[core_id]`
(Section 5.3). No runtime hashing of core sets is needed — the DFA
already assigns state IDs.

**Distance vector hashing at parse time.** Two positions with the
same DFA state may have different distance vectors (different origins
for the same items). YAEP's insight: if two positions also share the
same distance vector, they are structurally identical and the parse
will proceed identically from both.

A distance vector is the set of `(core_id, rel_dist)` pairs at a
position. The hash key is computed from these pairs:

```
dist_key = join(";", sort map { "$cid:$rd" } @pairs)
set_key  = "$state_id:$dist_key"
```

Two positions with the same `set_key` — same DFA state AND same
relative distances — are structurally identical. The set registry
tracks these for potential set reuse optimizations (prediction results,
completion patterns).

Distance vector hashing is parse-lifetime work (cleared between files).
It is optional — the parser is correct without it. It enables
measurement of set reuse frequency, which informs whether more
aggressive reuse optimizations (Appendix D) would be beneficial.

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

## 7. The Parse Loop

The parse loop is the runtime algorithm. It retains Earley's
agenda-driven structure — processing items one at a time through
predict, scan, and complete operations — while using the DFA and
distance factoring to reduce per-item overhead. The agenda loop is
preserved because Earley sets can contain items from multiple DFA
states (completions advance items from the origin's state into the
current position), and a single-state-per-position model would not
handle this correctly.

### 7.1 What the DFA Provides

The DFA does not replace the agenda loop. It optimizes three specific
operations within the loop:

**Prediction.** Standard Earley iterates all alternatives of a
nonterminal to add prediction items. With the DFA, prediction is a
state lookup: `dfa.prediction_items_for(nonterminal)` returns the
pre-clustered set of core_ids to add, including transitive predictions
and nullable-symbol advancement (Aycock-Horspool optimization).

**Terminal matching.** Standard Earley tries each terminal pattern per
item. With the DFA, each state has a *terminal map* listing the
distinct patterns expected by its items. The parser tries each pattern
once per position (not once per item) and caches the result. Items
sharing the same terminal pattern get immediate cache hits.

**Completion search.** Standard Earley searches all items at the
origin position for those waiting for the completed nonterminal. With
the DFA, each state has a *completion map* listing which core_ids wait
for each nonterminal. The search narrows from "all items at the origin"
to "only items in the origin state's completion map for this
nonterminal."

### 7.2 Data Structures

**Chart.** `chart[pos][core_id][rel_dist] = value`
- `pos`: input position (0 to N)
- `core_id`: integer from core item index
- `rel_dist`: `pos - origin` (relative distance, from Section 6)
- `value`: 5-element semiring tuple

**Completed index.** `completed_at[rule_name][origin][pos] = [(core_id, origin), ...]`
- Secondary index for completion lookups. Records which rules completed
  at which positions, for `_advance_from_completed` to use.

**Leo items.** `leo_items[rule_name][origin] = {top_core_id, top_origin, value, wait_core_id, wait_origin}`
- Side table for right-recursive chain shortcutting (Section 7.7).

**Processed items.** `processed[core_id][origin] = bool`
- Per-position deduplication to prevent re-processing the same item
  when it appears on the agenda multiple times (from merges).

**Scan cache.** `scan_cache[pos][pattern_string] = end_pos | undef`
- Per-position memoization of terminal regex matches. Populated by
  terminal clustering before the agenda loop; individual scan calls
  get cache hits.

### 7.3 The Algorithm

```
parse(input, grammar, dfa):
  N = length(input)
  chart = array of (N+1) empty slots

  # Cache DFA lookup arrays for hot-loop direct indexing
  ci_completions   = core_index.completions()
  ci_symbols_after = core_index.symbols_after()
  ci_rule_names    = core_index.rule_names()
  ci_alt_idxs      = core_index.alt_idxs()

  # Initialize: place start rule items at position 0
  start_rule = grammar[0]
  for each alt_idx of start_rule:
    core_id = core_index.id_for(start_rule.name, alt_idx, 0)
    chart[0][core_id][0] = semiring.one()

  for pos = 0 to N:

    # --- Build agenda from chart entries at this position ---
    agenda = []
    for each (core_id, rel_dist, value) in chart[pos]:
      push agenda, [core_id, pos - rel_dist]  # [core_id, origin]

    # --- DFA-driven prediction ---
    # For each active non-complete item, look up its DFA state via
    # state_for_core. The state's prediction closure provides all
    # nonterminals to predict. No hash computation or cache lookup.
    for each (core_id, origin) in agenda:
      if not ci_completions[core_id]:
        sym = ci_symbols_after[core_id]
        if sym and sym.is_reference():
          predict(sym.value, pos, chart, agenda, predicted_at)

    # --- DFA-driven terminal clustering ---
    # After predictions, collect terminal maps from the DFA states of
    # all active items. Each core_id maps to a DFA state (O(1) via
    # state_for_core). Each state has a precomputed terminal map.
    # Union the maps and try each distinct pattern once.
    if pos < N:
      seen_patterns = {}
      for each core_id with defined values at chart[pos]:
        state_id = state_for_core[core_id]
        tmap = dfa.state(state_id).terminal_map
        for each pattern in tmap:
          if not seen_patterns[pattern]:
            seen_patterns[pattern] = true
            if not in scan_cache[pos]:
              scan_cache[pos][pattern] = try_match(input, pos, pattern)

    # --- Agenda loop: predict, scan, complete ---
    processed = []

    while agenda not empty:
      (core_id, origin) = pop agenda

      # Dedup: skip if already processed
      if processed[core_id][origin]: skip
      processed[core_id][origin] = true

      # Re-read value from chart (may have been updated by a merge)
      value = chart[pos][core_id][pos - origin]

      if ci_completions[core_id]:
        # --- COMPLETE ---
        rule_name = ci_rule_names[core_id]
        alt_idx = ci_alt_idxs[core_id]
        completed_value = semiring.on_complete(
            value, rule_name, alt_idx, pos, origin)

        # Update chart with action-applied value
        chart[pos][core_id][pos - origin] = completed_value

        # Skip zero-valued completions
        if is_zero(completed_value): skip

        # Index this completion
        completed_at[rule_name][origin][pos].push([core_id, origin])

        # Propagate to waiting items (DFA-optimized)
        complete(core_id, origin, completed_value, pos, chart, agenda)

      else:
        sym = ci_symbols_after[core_id]
        rule_name = ci_rule_names[core_id]
        alt_idx = ci_alt_idxs[core_id]

        if sym.is_reference():
          # --- PREDICT ---
          predict(sym.value, pos, chart, agenda, predicted_at)

          # Handle ?-quantified optionals
          if sym.quantifier == '?':
            skip_value = semiring.on_skip_optional(
                value, rule_name, alt_idx, pos, sym.value)
            if not is_zero(skip_value):
              skip_core = advance(core_id)
              merge_into_chart(pos, skip_core, origin, skip_value, agenda)

          # Advance from already-completed items at this position
          advance_from_completed(core_id, origin, value, sym, pos, chart, agenda)

        else:
          # --- SCAN ---
          scan(core_id, origin, value, sym, pos, input, chart, N, agenda)

    # --- Post-position: GC ---
    # Safe-set and epoch GC (Sections 6.5)
    perform_gc(chart, pos)

  # --- Check for completed start rule at position N ---
  for each alt of grammar[0]:
    end_dot = length(alt)
    end_core_id = id_for(grammar[0].name, alt_idx, end_dot)
    value = chart[N][end_core_id][N]
    if defined(value) and not is_zero(value):
      return value

  return undef  # parse failure
```

### 7.4 Prediction with DFA Clustering

The `predict` function uses the DFA's precomputed prediction closures
instead of iterating grammar rules:

```
predict(rule_name, pos, chart, agenda, predicted_at):
  if predicted_at[rule_name]: return
  predicted_at[rule_name] = true

  # DFA provides all prediction items, including transitive
  # predictions and dot-advanced past nullable symbols
  prediction_items = dfa.prediction_items_for(rule_name)

  for each (core_id, skip_symbols) in prediction_items:
    if chart_has(pos, core_id, pos): skip  # already predicted

    # Build initial value, applying on_skip_optional for each
    # nullable symbol skipped to reach this dot position
    value = semiring.one()
    for each sym_name in skip_symbols:
      value = semiring.on_skip_optional(value, ..., sym_name)
      if is_zero(value): break

    if not is_zero(value):
      chart_set(pos, core_id, pos, value)
      push agenda, [core_id, pos]
```

The DFA's `prediction_items_for` returns the epsilon-closure: all
core_ids reachable by transitively following nonterminal references.
This includes items with dot > 0 for nullable-symbol advancement
(Aycock-Horspool optimization). The closure is computed once per
nonterminal at DFA construction time.

### 7.5 Completion with DFA Completion Maps

The `complete` function uses the DFA's completion map to narrow the
waiter search:

```
complete(completed_core_id, origin, completed_value, pos, chart, agenda):
  rule_name = rule_name_for(completed_core_id)

  # Leo optimization: check for deterministic chain
  if leo_enabled and leo_items[rule_name][origin] exists:
    resolve_leo(rule_name, origin, completed_value, pos, chart, agenda)

  # Find waiters: iterate global_waiting_core_ids for this nonterminal.
  # For each candidate, check chart[origin][waiter_core_id] to see if
  # the waiter is actually live at the origin. This is an O(1) array
  # access per candidate — no hash lookup or chart scan.
  chart_waiting_ids = global_waiting_core_ids[rule_name]

  if not defined(chart_waiting_ids): return

  for each waiter_core_id in chart_waiting_ids:
    oh = chart[origin][waiter_core_id]
    if not defined(oh): skip  # waiter not live at origin

    for each (waiter_value, waiter_origin) in oh:
      combined = semiring.multiply(waiter_value, completed_value)
      if is_zero(combined): skip

      target_core_id = advance(waiter_core_id)
      merge_into_chart(pos, target_core_id, waiter_origin, combined, agenda)

    # Leo creation: if exactly one waiter advanced successfully
    # and it would be complete after advancing, create a Leo item
    check_leo_creation(...)
```

**Completion indexing structures.** The completion step uses two
pre-built indexes and one runtime data structure:

1. `global_waiting_core_ids[nonterminal]` → `[core_id, ...]`
   - Built at grammar construction time.
   - For each nonterminal N, lists all core_ids in the grammar where
     the dot is immediately before N. These are the items that COULD
     be waiting for N to complete.
   - Typically 5-15 entries per nonterminal for the Perl grammar.

2. `completed_at[rule_name][origin][pos]` → `[(core_id, origin), ...]`
   - Built during parsing.
   - Records which rules completed at which positions, for the
     `advance_from_completed` operation (handling nullable nonterminals
     that complete at the same position where a new waiter appears).

3. `chart[origin][waiter_core_id][rel_dist]` → `value`
   - The chart itself is the runtime filter. For each candidate in
     `global_waiting_core_ids`, checking `chart[origin][waiter_core_id]`
     is an O(1) array access that determines whether the waiter is
     live at the origin.

The completion join key is `(nonterminal, origin)`:
- `nonterminal` selects the candidate list from `global_waiting_core_ids`
- `origin` selects the chart position to check for live waiters
- The chart check filters candidates to only those actually present

This avoids per-position chart scanning. The DFA provides the
structural knowledge (which core_ids could wait for which
nonterminals) at construction time. The chart provides the runtime
filter (which of those are actually live at this origin).

### 7.6 Scanning with Terminal Maps

The scan function uses the pre-populated scan cache from terminal
clustering:

```
scan(core_id, origin, value, symbol, pos, input, chart, N, agenda):
  pattern = symbol.value()

  # Check scan cache (populated by terminal clustering above)
  end_pos = scan_cache[pos][pattern]
  if end_pos is undef: return  # no match

  matched_text = substr(input, pos, end_pos - pos)

  # Gate: ask semiring if scan should proceed
  if not semiring.should_scan(value, rule_name, alt_idx, pos, matched_text, predicted_at):
    return

  # Apply on_scan
  new_value = semiring.on_scan(value, rule_name, alt_idx, pos, matched_text)
  if is_zero(new_value): return

  # Advance dot and add to next position's chart
  new_core_id = advance(core_id)
  merge_into_chart(end_pos, new_core_id, origin, new_value, agenda)
```

Terminal clustering before the agenda loop pre-scans all patterns
expected by the active items' DFA states. The scan function finds the
result in the cache — no regex execution during the agenda loop. The
terminal maps are precomputed at DFA construction time, so no lazy
discovery or chart scanning is needed.

**Interaction between terminal clustering and `should_scan`.** Terminal
clustering determines WHETHER a pattern matches at a position — a
property of the input text, independent of any item. The `should_scan`
gate determines whether a SPECIFIC ITEM should use that match — a
property of the item's semiring value and the parser's prediction
state. These are separate concerns operating at different levels:

- Terminal clustering: per-position, per-pattern. Caches the regex
  result (matched text or undef).
- `should_scan`: per-item. Consults the item's accumulated value and
  the predicted-rules set to decide whether to proceed with the scan.

The same terminal pattern might match at a position but be accepted by
`should_scan` for one item and rejected for another. For example, the
word `class` matches the `\w+` terminal, but `should_scan` in
TypeInference rejects it for QualifiedIdentifier items when a
ClassDeclaration rule is predicted (because `class` is a keyword in
that context). Other items expecting `\w+` (e.g., in a method name
position) accept the same match.

An implementer must not skip the `should_scan` gate just because the
terminal clustering found a match. The cache provides the regex result;
the gate filters per-item.

### 7.7 Scannerless Whitespace Handling

This parser is *scannerless* — it has no separate lexer. Whitespace
and comments are grammar terminals matched by the same mechanism as
keywords and operators. The Perl grammar uses a whitespace terminal
with the pattern `(?:\s|#[^\n]*)*` (zero or more whitespace characters
or line comments). This pattern appears in most grammar rules between
significant tokens.

Scannerless whitespace has three properties that affect the parser:

**Zero-width matches.** The whitespace pattern uses `*` (zero or more),
so it matches the empty string at every position. A zero-width match
advances the item's dot but does NOT advance the input position. The
advanced item is added to the CURRENT position's agenda (not the next
position's chart). The agenda loop processes it immediately.

This means: at every position, the whitespace terminal matches. Every
item expecting whitespace advances past it (to the same position) and
continues to the next symbol in its rule. Whitespace consumption is
invisible to the position-level loop — it happens within a single
position's agenda processing.

**Ubiquity in terminal maps.** Because most DFA states contain items
expecting whitespace, most states' terminal maps include the whitespace
pattern. Terminal clustering tries it at every position and it always
matches (zero-width at minimum). This is correct but means the
whitespace pattern never enables quick-reject filtering — it always
produces a hit.

**Impact on scan cache.** The scan cache at every position contains
an entry for the whitespace pattern. Since the match is always
successful (at least zero-width), this cache entry is always populated.
The cost is one regex execution per position for whitespace, regardless
of DFA state.

**Grammar design implication.** The whitespace terminal should use a
single shared pattern across all rules. If different rules used
different whitespace patterns (e.g., one allowing newlines, another
not), the terminal map would contain multiple whitespace entries and
each would be tried. A single canonical whitespace pattern minimizes
redundant matching.

### 7.8 Leo Optimization

The Leo optimization handles right-recursive rules in O(1) per
recursive step instead of O(n). When a completion is *deterministic*
(exactly one waiting item, and that item would be complete after
advancing), the parser creates a Leo item that represents the entire
chain.

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

### 7.9 Merge Protocol

When adding a value to a chart cell that already contains a value:

```
merge_into_chart(pos, core_id, origin, new_value, agenda):
  rel_dist = pos - origin
  existing = chart[pos][core_id][rel_dist]

  if not defined(existing):
    chart[pos][core_id][rel_dist] = new_value
    push agenda, [core_id, origin]  # new item — add to agenda
    return

  # Existing item — merge via semiring add
  merged = semiring.add(existing, new_value)
  chart[pos][core_id][rel_dist] = merged
```

The semiring `add` resolves ambiguity: Precedence picks the better
operator grouping, Structural picks block over hash, TypeInference
provides type information for the choice. FilterComposite's first-wins
ordered priority determines which semiring's preference takes effect.

### 7.10 DFA State at Runtime

The DFA is constructed fully at grammar construction time (Section 5).
At parse time, no state discovery or chart scanning is needed. The
DFA state for any item is determined by `state_for_core[core_id]` —
an O(1) array lookup precomputed during DFA construction.

When the parser needs DFA state properties during the agenda loop:

- **For terminal clustering**: collect the DFA states of all active
  items at the position, then union their terminal maps. In practice,
  most items at a position share one or two DFA states, so the union
  is small.

- **For completion**: look up `state_for_core[waiter_core_id]` to get
  the waiter's DFA state, then use that state's completion map. This
  is O(1) per waiter — no chart scanning, no hash-key computation.

- **For prediction**: look up `dfa.prediction_items_for(nonterminal)`,
  which returns the epsilon-closure precomputed at DFA construction
  time. The DFA state is implicit in the prediction closure.

This eliminates the runtime cost of core set discovery (previously
O(chart width) per position with hash-key string construction and
registry lookup). The DFA state is always known from the core_id.

### 7.11 Worked Example: Parsing `2+3`

Using the grammar and DFA from Section 5.4:

**Position 0.** Agenda: `{[0,0], [4,0], [6,0]}` (Expr->., Expr->., Term->.)

- Item [0,0]: `Expr -> . Expr '+' Term`. Dot before nonterminal Expr.
  Predict Expr — already predicted.
- Item [4,0]: `Expr -> . Term`. Dot before nonterminal Term.
  Predict Term — adds [6,0] (already present).
- Item [6,0]: `Term -> . 'number'`. Dot before terminal `\d+`.
  Scan: matches `2` (pos 0..1). Add [7,0] to chart[1].

Core set discovered: {0, 4, 6}. Terminal map: `{'\d+' -> [6]}`.
Completion map: `{Expr -> [0], Term -> [4]}`.

**Position 1.** Agenda: `{[7,0]}` (from scan).

- Item [7,0]: `Term -> 'number' .` — complete! Rule Term, origin 0.
  on_complete: TypeInference assigns type Int.
  Complete Term: completion map at origin (core set {0,4,6}) says
  core_id 4 waits for Term. chart[0][4] has value at rel_dist 0.
  Multiply: waiter_value * completed_value. Advance core_id 4 → 5.
  Add [5,0] to chart[1].

- Item [5,0]: `Expr -> Term .` — complete! Rule Expr, origin 0.
  on_complete: transparent (Expr passes through).
  Complete Expr: completion map says core_id 0 waits for Expr.
  chart[0][0] has value at rel_dist 0.
  Multiply. Advance core_id 0 → 1.
  Add [1,0] to chart[1].

- Item [1,0]: `Expr -> Expr . '+' Term`. Dot before terminal `+`.
  Scan: matches `+` (pos 1..2). Advance to [2,0] at chart[2].
  Precedence on_scan: records level 3, left-associative.

**Position 2.** Agenda: `{[2,0]}`.

- Item [2,0]: `Expr -> Expr '+' . Term`. Dot before nonterminal Term.
  Predict Term — adds [6,2] to chart[2].

- Item [6,2]: `Term -> . 'number'`. Scan: matches `3` (pos 2..3).
  Add [7,2] to chart[3].
  TypeInference on_scan: assigns type Int.

**Position 3.** Agenda: `{[7,2]}`.

- Item [7,2]: `Term -> 'number' .` — complete! Origin 2.
  Complete Term: completion map at origin position 2 (core set
  discovered as {2, 6}) says core_id 2 waits for Term.
  chart[2][2] has value at rel_dist 0.
  Multiply. Advance core_id 2 → 3. Add [3,0] to chart[3].
  TypeInference: check `+` signature (Num, Num) -> Num.
  Left operand Num, right operand Int (satisfies Num). Result: Num.

- Item [3,0]: `Expr -> Expr '+' Term .` — complete! Origin 0.
  This is the start rule complete at the end of input. Parse succeeds.

---

## 8. Error Detection, Diagnostics, and Recovery

### 8.1 Error Detection

A parse fails when no complete start-rule item exists at position N.
The parser detects this by checking `chart[N]` for the start rule.

The parser tracks the *last active position*: the furthest input
position where any item had a defined value. If the last active
position is less than N, the input was not fully consumed. The
difference between last active position and N indicates where parsing
stalled.

### 8.2 Diagnostics

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

### 8.3 Error Recovery

Error recovery allows the parser to continue past syntax errors,
producing partial parse results and additional diagnostics.

**Statement-level recovery.** When the parser detects failure at
position P:

1. Record the error and expected tokens at P.
2. Scan forward from P to find the nearest *synchronization token*:
   a statement terminator (`;`), block closer (`}`), or declaration
   keyword (`method`, `field`, `class`).
3. Skip the input between P and the synchronization point.
4. Resume parsing from the grammar's statement-start DFA state at the
   synchronization point.

**Why statement-level, not backward-walking.** Safe-set GC
(Section 6.5) frees chart data at statement boundaries. Walking
backward to find a safe-set boundary would find freed positions with
no chart data. Statement-level recovery avoids this: instead of
reconstructing parser state from a freed position, it resets to a
known DFA state (the state that begins a new statement). This is the
same state the parser enters after every `;` during normal parsing.

**Recovery state selection.** The statement-start DFA state is
identified during DFA construction: it is the state containing the
prediction closure for the Statement nonterminal. This state is the
same at every statement boundary, so the parser can resume with
`semiring.one()` values and parse the next statement independently.

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

## 9. Grammar Construction and BNF Bootstrap

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

## 10. Code Generation Pipeline

The parser produces a composite semiring value containing an IR tree
(from SemanticAction) annotated with type information (from
TypeInference). This section describes the pipeline from parse result
to compiled output.

### 10.1 The IR: Sea of Nodes

The IR uses a Sea of Nodes representation:

- **Data nodes**: Constant, BinaryOp, UnaryOp, Call, FieldAccess
- **Control nodes**: Start, Return, If, Region, Loop
- **Structure nodes**: Constructor (ClassDecl, MethodDecl, FieldDecl, etc.)

All nodes are immutable and hash-consed. Identical subexpressions share
the same node object.

### 10.2 Pipeline Stages

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

### 10.3 C Code Generation

The code generator (Target::C) translates IR nodes to C functions:

- Each class in the source becomes a C file with exported functions.
- Field access uses Perl's `ObjectFIELDS` API.
- Method dispatch uses either direct C calls (when the target class is
  known from type information) or `call_method` (generic dispatch).
- The DFA tables can be emitted as static C arrays, making the parser
  itself compilable to C.

### 10.4 XS Wrappers

Each generated C file gets a thin XS wrapper that:
- Registers the C functions as Perl methods (via BOOT block)
- Sets up field attributes (:param, :reader, :writer) using the
  Perl 5.42 class C API
- Handles ADJUST blocks as native XSUBs

The result is a shared library (`.so`) that Perl loads at runtime,
replacing the pure-Perl implementation with compiled C.

### 10.5 Type Information in Code Generation

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

## 11. Performance Analysis

### 11.1 Complexity

**Standard Earley**: O(n^3) worst case, O(n^2) unambiguous, O(n) LR(k).
The constant factors are dominated by item allocation, hash-based
membership testing, and redundant prediction.

**DFA-factored Earley**: Same asymptotic complexity, but with smaller
constant factors:

| Operation | Standard | DFA-factored |
|-----------|----------|-------------|
| Prediction | O(rules) per position | O(1) DFA closure lookup |
| Membership | Hash lookup per item | Array index per core_id |
| Completion search | O(items at origin) | O(waiters in completion map) |
| Terminal matching | O(items * patterns) | O(patterns in terminal map) |
| Core set discovery | O(chart width) per position | O(chart width) first encounter, O(1) cached |

The DFA-factored parser reduces per-position overhead through cached
prediction closures, precomputed completion maps, and terminal
clustering. Core set discovery retains an O(chart width) scan but
caches the result for future positions with the same active items.
The agenda loop is preserved for correctness — it handles the
nondeterministic merging of items from multiple DFA states at the
same position.

### 11.2 Set Reuse Impact

For repetitive source code (common in real programs), set reuse avoids
redundant work:

- **Prediction reuse**: positions with the same DFA state share
  predictions. In a file with 100 statements, statement-start
  predictions are computed once and reused 99 times.

- **Completion map reuse**: the completion map for a DFA state is
  computed once. All positions in that state use the same map.

- **Terminal map reuse**: terminal matching patterns are tried once per
  DFA state per position, not once per item.

### 11.3 Memory

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

### 11.4 Benchmark Methodology

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

### 11.5 Scope Limitations

**Incremental parsing** (reparsing after edits, IDE integration) is
out of scope for this design. The parser processes complete source
files from start to finish. The DFA and distance factoring are
optimized for batch parsing — chart positions reference earlier
positions via relative distances, and GC frees intermediate positions.
Incremental updates (inserting or deleting text) would invalidate
distances and require re-parsing from the edit point.

Future work could explore incremental extensions:
- **Tree-sitter style**: maintain a concrete syntax tree and reparse
  only the affected subtree. The DFA state at the edit boundary
  determines where to resume.
- **Chart checkpointing**: save chart state at safe-set boundaries
  (statement-level). After an edit, restore the most recent checkpoint
  before the edit and reparse from there.

These are research directions, not part of the current specification.

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

**Operation table.** (Future optimization, Appendix D.) Per DFA state:
an array of entries describing every operation the parser performs in
that state, with precomputed semiring columns. Speculative — requires
the single-state-per-position assumption that has not been validated.

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

---

## Appendix D: Operation Table Design (Future Optimization)

This appendix describes a speculative optimization that goes beyond the
proven Aycock and YAEP techniques. It has not been validated and should
be treated as a research direction, not a specification.

### D.1 The Idea

The agenda loop in Section 7 processes items one at a time, dispatching
to predict, scan, or complete based on each item's properties. The DFA
precomputes *which* operations will happen (terminal maps, completion
maps, prediction closures), but the loop still decides *how* to handle
each item at runtime — reading the core_id, looking up the symbol after
the dot, branching on terminal vs. nonterminal, calling the appropriate
semiring methods.

The operation table eliminates this per-item dispatch by precomputing
the complete sequence of operations for each DFA state. Instead of "for
each item, decide what to do," the parser executes "for this state,
here is what to do" — a table of entries, each with precomputed
semiring operation descriptors.

### D.2 Table Structure

An operation table is an array of entries, one per core_id in the DFA
state. Each entry describes the operation for that core_id:

```
Entry = {
  op_type:     'complete' | 'scan' | 'predict' | 'skip_optional'
  core_id:     the core item this entry applies to
  rule_name:   precomputed from core_id
  alt_idx:     precomputed from core_id

  # For 'complete':
  target_state:  DFA state after advancing past the completed nonterminal
  waiters:       [core_ids waiting for this nonterminal]

  # For 'scan':
  pattern:       terminal regex pattern
  target_state:  DFA state after advancing past the terminal
  compiled_re:   precompiled regex object

  # Semiring columns (one per semiring, expressed as data):
  boolean_op:    'identity' | 'check_zero'
  prec_op:       'identity' | 'reset' | 'assign_level' | 'pass_through'
  prec_level:    integer (for 'assign_level')
  type_op:       'identity' | 'check_signature' | 'assign_type'
  type_result:   Type bitset (for 'assign_type')
  type_sig:      {left: Type, right: Type, result: Type}
  struct_op:     'identity' | 'tag'
  struct_bits:   integer bitfield (for 'tag')
  sa_action:     reference to semantic action function
}
```

Each semiring's contribution is compiled to a data descriptor at DFA
construction time. At parse time, the executor reads the descriptor
and applies it — a switch on a small enum, not a method call through
the full semiring dispatch chain.

### D.3 Why This Is Speculative

The operation table assumes that each position can be processed as a
single DFA state. Earley parsing is nondeterministic: completions at
position P advance items from the origin's state into P, producing
items that may belong to different DFA states. A position's items are
the union of items from multiple goto transitions.

Aycock's dissertation retains the agenda loop precisely because of this
nondeterminism. The DFA optimizes prediction and terminal clustering
but does not replace the per-item loop.

The operation table would work correctly only if one of the following
holds:

1. **Single-state dominance.** Most positions are dominated by one DFA
   state (from scanning). Completion-produced items from other states
   are rare and can be handled by a fallback path. This needs empirical
   validation.

2. **State merging.** Positions where multiple DFA states contribute
   items could be handled by a merged operation table (union of the
   contributing states' tables). This preserves correctness but reduces
   the benefit if many states merge frequently.

3. **Phased processing.** Process scans via operation table (single
   state, deterministic), then process completions via the agenda loop
   (nondeterministic). This hybrid captures the scan benefit without
   requiring single-state positions.

### D.4 Potential Benefit

Profiling of the current parser shows that 72% of parse time is
overhead — agenda building, processed-item deduplication, chart
scanning, symbol dispatch. Only 5% is semiring operations and 23%
is in the predict/scan/complete methods themselves.

The operation table targets the 72% overhead by replacing the agenda
loop's per-item branching with table-driven execution. If the
single-state assumption holds for 90%+ of positions, the operation
table could reduce per-position overhead significantly — potentially
the largest constant-factor improvement available.

However, this has not been implemented or benchmarked. The agenda-loop
architecture in Section 7 is the proven design. The operation table
should be pursued only after the Section 7 design is implemented,
validated, and profiled, providing empirical data on DFA state
distribution and single-state frequency.

### D.5 Relationship to Partially-Applied Functions

The operation table can be viewed as a partially-applied function per
DFA state. The DFA state determines the *structure* of the operation
(which rules complete, which terminals to scan, which semiring
operations to apply). The per-position values provide the *arguments*.

Each entry's semiring columns are the partial application: the
`prec_op: 'assign_level', prec_level: -2` entry for PostfixExpression
is the partial application `sub ($v) { _intern(true, -2, undef, false) }`.
The table representation makes this inspectable and serializable where
closures would be opaque.

If the operation table proves feasible, the natural evolution is to
compile the tables to C code (via Target::C), producing a
directly-executable parser where each DFA state is a C function that
processes its entries without interpretation overhead. This is Aycock's
SHALLOW concept (directly-executable Earley parsing) applied to the
operation table architecture.
