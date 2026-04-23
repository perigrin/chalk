# Ambiguity Classes in Chalk's Grammar

## Overview

Chalk's grammar is intentionally ambiguous in four known classes.
The grammar + Boolean semiring produces multiple derivations only
for inputs that fall into one of these classes. Any other ambiguity
is a grammar bug.

Each class has a dedicated filtering semiring responsible for
resolving it. By the time SemanticAction fires, the parse is
unambiguous — SemanticAction never disambiguates.

## Class 1: Precedence

**Semiring:** Precedence

**What:** Binary operator binding order and named-function arity.

**Examples:**
```perl
$a + $b * $c        # * binds tighter than +
$x || $y && $z      # && binds tighter than ||
defined $x + 1      # defined is named-unary (high prec): (defined $x) + 1
print $x + 1        # print is list-op (low prec): print($x + 1)
push @arr, $x . $y  # push is list-op: push(@arr, $x . $y)
```

**Mechanism:** PrecedenceTable assigns a numeric precedence to each
binary operator and to each builtin function based on its arity
class:

- **Named unary** (`defined`, `ref`, `exists`, `delete`, `chr`,
  `ord`, `length`, `scalar`, `keys`, `values`, `each`): high
  precedence, binds tighter than arithmetic. Equivalent to
  toke.c's `UNI`/`FUN1`.
- **List operator** (`print`, `say`, `warn`, `push`, `unshift`,
  `pop`, `shift`, `splice`, `sort`, `reverse`, `chomp`, `chop`,
  `join`, `split`, `substr`, `sprintf`, `map`, `grep`): low
  precedence on the right, absorbs everything up to the next
  statement boundary or comma-separated list end. Equivalent to
  toke.c's `LOP`.

**Grammar rule:** `CallExpression ::= QualifiedIdentifier WS
ExpressionList` handles both forms syntactically. Precedence
semiring selects which derivation's binding is correct.

## Class 2: Type / Keyword

**Semiring:** TypeInference

**What:** Two sub-classes resolved by type-level knowledge.

### 2a: Keyword vs identifier

A word like `class`, `return`, `if`, `sub` could be a
`QualifiedIdentifier` (function name, hash key) or the start of a
dedicated grammar rule (`ClassBlock`, `ReturnStatement`,
`IfStatement`, `SubroutineDefinition`).

**Examples:**
```perl
class Foo { }        # keyword: ClassBlock
$hash{class}         # identifier: hash key (but actually a quoted key)
class => 'Foo'       # identifier: fat-arrow LHS
return $x            # keyword: ReturnStatement
```

**Mechanism:** `KeywordTable::is_keyword()` identifies keywords.
`TypeInference::should_scan()` rejects `QualifiedIdentifier` scans
for keywords when the keyword's consuming rule is predicted. The
fat-arrow case works because `ClassBlock` is not predicted in
`ExpressionList` context.

### 2b: Regex vs division

`/pattern/` could be a regex literal or two division operators
around a bareword.

**Examples:**
```perl
my $re = /foo/;      # regex literal (Regex type expected)
my $x = $a / $b;     # division (Num type expected)
```

**Mechanism:** TypeInference resolves based on the expected type in
context. A Regex and a division BinaryExpr are almost never both
type-valid in the same position.

## Class 3: Structural

**Semiring:** Structural

**What:** `{ }` as Block (control flow) vs HashConstructor (data).

**Examples:**
```perl
if ($x) { $y }       # Block (follows conditional)
my $h = { a => 1 }   # HashConstructor (RHS of assignment)
map { $_->method } @arr  # Block (first arg to map)
```

**Mechanism:** Structural semiring uses context tags (`is_block`,
`is_hash`) to resolve. Tags propagate based on the enclosing
grammar rule.

## Class 4: Block-first builtins

**Semiring:** Precedence + TypeInference (cooperative)

**What:** `map`, `grep`, `sort` accept either `BLOCK LIST` or
`EXPR, LIST` as first argument.

**Examples:**
```perl
map { $_->name } @items     # Block form
map { name => $_ }, @items  # EXPR form (hash constructor)
sort { $a <=> $b } @items   # Block form
sort @items                 # No block
```

**Mechanism:** Grammar provides both alternatives via
`CallExpression`. Structural semiring distinguishes Block vs Hash
for the `{ }`. TypeInference validates that the block/expression
type is consistent with the builtin's signature.

## Invariants

1. **Grammar + Boolean produces ambiguity ONLY in these four
   classes.** Any input that produces ambiguity outside these
   classes is a grammar bug.

2. **Each filtering semiring resolves exactly its own class.**
   Precedence does not resolve keyword/identifier ambiguity.
   TypeInference does not resolve operator binding. Structural
   does not resolve arity.

3. **SemanticAction never disambiguates.** By the time SA fires,
   exactly one derivation survives. SA transforms a Context into
   IR without choosing between alternatives.

4. **`_fixup_stmts` is a violation of these invariants.** Every
   case in `_fixup_stmts` represents a failure of the grammar or
   the filtering semirings to resolve an ambiguity before SA fires.
   The goal is to eliminate `_fixup_stmts` by fixing the grammar
   and semirings so these invariants hold.

## Relationship to toke.c

Perl's `toke.c` bundles disambiguation into the tokenizer via
`PL_expect` (XTERM/XOPERATOR) and per-keyword classifications
(KEY_*, FUN0, FUN1, UNI, LOP, LSTOP). Chalk distributes the same
disambiguation across separate semirings:

| toke.c mechanism | Chalk equivalent |
|-----------------|-----------------|
| XTERM/XOPERATOR | Precedence semiring |
| KEY_* constants | KeywordTable + TypeInference |
| FUN1/UNI vs LOP | PrecedenceTable (arity classification) |
| Block/hash heuristics | Structural semiring |
| Regex/division context | TypeInference |

This separation is deliberate: each concern is testable in
isolation, composable via FilterComposite, and extensible without
modifying the grammar.
