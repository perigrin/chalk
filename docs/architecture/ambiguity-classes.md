# Ambiguity Classes in Chalk's Grammar

## Overview

Chalk's grammar is intentionally ambiguous in seven known classes.
The grammar + Boolean semiring produces multiple derivations only
for inputs that fall into one of these classes. Any other ambiguity
is a grammar bug.

Each class has a dedicated filtering semiring responsible for
resolving it. By the time SemanticAction fires, the parse is
unambiguous — SemanticAction never disambiguates.

Two classes from the general Perl-parsing landscape are **excluded
by restriction** rather than resolved by a semiring:

- **Indirect object notation** (`new Foo` vs `new(Foo)`) — not
  supported in Chalk.
- **Bareword resolution** (filehandle vs class name vs function vs
  hash key vs label) — Chalk restricts this: hash keys must be
  quoted, filehandles are not barewords, labels are not yet
  supported. The remaining bareword case is "function name" and
  is handled as `QualifiedIdentifier`.

## Class 1: Precedence

**Semiring:** Precedence

**What:** Binary operator binding order.

**Examples:**
```perl
$a + $b * $c        # * binds tighter than +
$x || $y && $z      # && binds tighter than ||
$a ? $b : $c ? $d : $e    # right-associative ternary
```

**Mechanism:** PrecedenceTable assigns a numeric precedence to each
binary operator. Precedence semiring selects the derivation whose
tree matches the precedence specification.

## Class 2: Keyword vs identifier

**Semiring:** TypeInference

**What:** A word like `class`, `return`, `if`, `sub` could be a
`QualifiedIdentifier` or the start of a dedicated grammar rule.

**Examples:**
```perl
class Foo { }        # keyword: ClassBlock
class => 'Foo'       # identifier: fat-arrow LHS
return $x            # keyword: ReturnStatement
if ($x) { ... }      # keyword: IfStatement
```

**Mechanism:** `KeywordTable::is_keyword()` identifies keywords.
`TypeInference::should_scan()` rejects `QualifiedIdentifier` scans
for keywords when the keyword's consuming rule is predicted. The
fat-arrow case works because `ClassBlock` is not predicted in
`ExpressionList` context.

## Class 3: Block vs hash constructor

**Semiring:** Structural

**What:** `{ ... }` as Block (control flow / anonymous scope) vs
HashConstructor (data).

**Examples:**
```perl
if ($x) { $y }           # Block (follows conditional)
my $h = { a => 1 }       # HashConstructor (RHS of assignment)
map { $_->name } @arr    # Block (first arg to map, see class 7)
return { a => 1 }        # HashConstructor (return value)
```

**Mechanism:** Structural semiring uses context tags (`is_block`,
`is_hash`) to resolve. Tags propagate based on the enclosing
grammar rule.

## Class 4: Slash as division vs regex delimiter

**Semiring:** TypeInference

**What:** `/pattern/` could be a regex literal or two division
operators around a bareword/expression.

**Examples:**
```perl
my $re = /foo/;      # regex literal (Regex type)
my $x = $a / $b;     # division (Num type)
$x =~ /foo/          # regex (binding operator context)
```

**Mechanism:** TypeInference resolves based on the expected type in
context. A Regex and a division BinaryExpr are almost never both
type-valid in the same position. Chalk also restricts bare regex
to single lines to further constrain the ambiguity.

## Class 5: Named unary vs list operator

**Semiring:** Precedence

**What:** Builtins differ in how much of the following expression
they absorb. Named unaries take one argument at high precedence;
list operators absorb everything to the next statement boundary or
comma-separated list end at very low precedence.

**Examples:**
```perl
defined $x + 1       # named unary: (defined $x) + 1
print $x + 1         # list operator: print($x + 1)
push @arr, $x . $y   # list operator: push(@arr, $x . $y)
keys %h + 1          # named unary: (keys %h) + 1
```

**Mechanism:** PrecedenceTable classifies each builtin by arity:

- **Named unary** (`defined`, `ref`, `exists`, `delete`, `chr`,
  `ord`, `length`, `scalar`, `keys`, `values`, `each`): high
  precedence.
- **List operator** (`print`, `say`, `warn`, `push`, `unshift`,
  `pop`, `shift`, `splice`, `sort`, `reverse`, `chomp`, `chop`,
  `join`, `split`, `substr`, `sprintf`): very low precedence on
  the right.

Grammar rule `CallExpression ::= QualifiedIdentifier WS
ExpressionList` handles both forms syntactically. Precedence
semiring selects which derivation's binding is correct.

## Class 6: Unary minus vs binary minus

**Semiring:** Precedence (with help from grammar structure)

**What:** `-` can be a unary prefix (negation) or a binary operator
(subtraction).

**Examples:**
```perl
my $x = -5           # unary minus
my $x = 3 - 2        # binary minus
my $x = -$y + 3      # unary minus then binary plus: (-$y) + 3
my $x = 3 - -$y      # binary minus, unary minus
```

**Mechanism:** The grammar has distinct `UnaryExpression` and
`BinaryExpression` rules; `-` appears in both. The Precedence
semiring uses the position (expecting a term → unary; expecting an
operator → binary) to select the correct derivation. This is
equivalent to toke.c's `PL_expect` XTERM/XOPERATOR state.

## Class 7: map/grep/sort BLOCK vs EXPR form

**Semiring:** Structural (for block/hash distinction) + Precedence

**What:** `map`, `grep`, `sort` accept either `{ BLOCK } LIST` or
`EXPR, LIST` as first argument.

**Examples:**
```perl
map { $_->name } @items         # Block form
map name => $_, @items          # EXPR form (fat-arrow pair)
sort { $a <=> $b } @items       # Block form
sort @items                     # No block: default ordering
grep { defined $_ } @items      # Block form
grep defined($_), @items        # EXPR form
```

**Mechanism:** Grammar provides both alternatives via
`CallExpression ::= QualifiedIdentifier WS Block WS ExpressionList`
(block form) and `CallExpression ::= QualifiedIdentifier WS
ExpressionList` (expr form). Structural semiring distinguishes
Block from HashConstructor for the `{ }`. Precedence ensures the
arguments bind correctly to the builtin.

## Invariants

1. **Grammar + Boolean produces ambiguity ONLY in these seven
   classes.** Any input that produces ambiguity outside these
   classes is a grammar bug.

2. **Each filtering semiring resolves exactly its own class(es).**
   Precedence resolves operator binding and builtin arity (classes
   1, 5, 6). TypeInference resolves keyword/identifier and
   regex/division (classes 2, 4). Structural resolves block/hash
   (classes 3, 7).

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
| XTERM/XOPERATOR | Precedence semiring (classes 1, 6) |
| KEY_* constants | KeywordTable + TypeInference (class 2) |
| FUN1/UNI vs LOP | PrecedenceTable arity classification (class 5) |
| Block/hash heuristics | Structural semiring (classes 3, 7) |
| Regex/division context | TypeInference (class 4) |
| Indirect object heuristics | Excluded from Chalk |
| Bareword heuristics | Restricted (quoted hash keys, no filehandles) |

This separation is deliberate: each concern is testable in
isolation, composable via FilterComposite, and extensible without
modifying the grammar.
