# Chalk Self-Hosting Roadmap

> **Scope:** This document is the multi-phase implementation plan for
> extending Chalk to parse Perl 5.42 source. For the Chalk project as
> a whole, see [`../README.md`](../README.md).

## Strategy

Extend the existing BNF-to-Perl pipeline to parse Perl 5.42.0 source
code, ultimately self-hosting by compiling the 37+ `.pm` files under `lib/Chalk/`.

The approach has two major stages:

1. **Progressive grammar recognition (Phases 1-5)**: Feed increasingly larger
   subsets of the 65-rule Perl grammar (`docs/chalk-bootstrap.bnf`) through the
   existing BNF pipeline. Use synthetic test inputs. Add disambiguation semirings
   and Aycock parser optimizations as needed — not before.

2. **File-driven compilation (Phases 6-8)**: Walk through actual Chalk source
   files from simplest to most complex, building IR, then lowering to Perl, then
   lowering to XS. Same phasing as the BNF pipeline that already works.

Three concrete advantages:

1. **Each phase is testable.** Synthetic inputs prove correctness before touching
   real source files.
2. **Infrastructure arrives when needed.** Semirings and optimizations are built
   in response to actual failures (ambiguity, performance), not in anticipation.
3. **The hardest problems arrive late.** Expression disambiguation is Phase 4;
   complex source files are Phases 6-8.

**IMPORTANT — Before starting any phase**: The implementing agent MUST read
`CLAUDE.md` to load project conventions, required skills, development workflow,
and the triple-review process. CLAUDE.md is the authoritative source for how
work is done; this plan is the authoritative source for what work to do.

-----

## Architecture

### Semiring Composition

The canonical five-semiring FilterComposite pipeline is documented in
[`architecture/parsing-pipeline.md`](architecture/parsing-pipeline.md). This
plan assembles its phases against that pipeline.

**ChalkSyntax** — The disambiguating recognizer (the four filtering semirings):

```
ChalkSyntax = FilterComposite(Boolean, Precedence, TypeInference, Structural)
```

Produces exactly ONE unambiguous parse. All disambiguation happens during the
parse via `add()`. No post-parse filtering.

**ChalkIR** — Layers IR construction on top:

```
ChalkIR = FilterComposite(Boolean, Precedence, TypeInference, Structural, SemanticAction)
```

The four filtering semirings MUST produce one unambiguous parse before
SemanticAction generates IR. This is the cardinal rule from
`docs/architecture/parsing-pipeline.md`.

### Staged Filter in `add()`

When two alternative parses meet at the same chart item, ChalkSyntax's `add()`
consults component semirings as a staged filter with short-circuit rejection.
The four filtering semirings commute — reordering them does not change which
parses are accepted, only how quickly they are rejected. The canonical order
is a performance choice (cheapest/most-discriminating filters first):

```
Boolean        → reject? done (cheapest check)
Precedence     → reject? done
TypeInference  → reject? done
Structural     → reject? done
keep the survivor
```

Any future reordering (e.g. moving TypeInference earlier to prune more
aggressively) is a performance tuning decision, not a correctness one.

### ConciseTree Semiring

A purpose-built semiring that produces output comparable to `perl -MO=Concise,-exec`.
Used for structural validation: our parse tree should match Perl's understanding
of the same source code. This is the oracle that catches:

- **Missing operations**: Chalk forgot to emit an op that Perl generates
- **Wrong operation**: Chalk chose string-eq where Perl chose numeric-eq
- **Structural divergence**: Chalk generated flat where Perl generated conditional

### Aycock Optimizations

See `docs/chalk-ayock-optimizations.md` for the full design. Key techniques:

- **LR(0) DFA prediction**: Collapses N predicted items into 1 DFA state
- **Bitmap chart membership**: `vec()` bit checks instead of hash lookups
- **Safe-set GC**: Release chart positions that can't be reached by future completions
- **Lazy semiring init**: Defer full composite element creation until item proves viable
- **Terminal clustering**: Match each regex once per DFA state, not once per item

These are pulled in **if and when** performance demands during Phases 1-5.
The existing Earley parser should handle the 65-rule grammar; if it doesn't,
that's the signal.

### Reference Documentation

| Document               | Location                              | Relevance                                 |
|------------------------|---------------------------------------|-------------------------------------------|
| Semiring Architecture  | `pu:docs/semiring-architecture.md`    | Cardinal rule: one parse before IR        |
| Precedence Semiring    | `pu:docs/precedence-semiring.md`      | Active/passive model, table-driven design |
| Type System (Grammar)  | `pu:docs/chalk-grammar-types.md`      | Type lattice: Int <: Num <: Str <: Scalar |
| Type Mapping (IR)      | `pu:docs/chalk-ir-type-mapping.md`    | Grammar ↔ IR type bridge                  |
| Perl Types (Practical) | `pu:docs/perl-types-practical.md`     | Round-trip + behavioral membership tests  |
| Aycock Optimizations   | `docs/chalk-ayock-optimizations.md`   | Parser performance techniques             |
| Aycock Dissertation    | `docs/Aycock_JohnDaniel_PhD_2001.pdf` | Parser design + performance               |
| Perl Grammar Spec      | `docs/perlish-grammar-spec.md`        | 65-rule grammar, 20 sections              |
| BNF Grammar File       | `docs/chalk-bootstrap.bnf`            | Machine-readable grammar                  |

-----

## Concrete Deliverables

### A. Perl Operator Precedence Table

Derived from perlop. Lower level number = higher precedence (binds tighter).
The Precedence semiring uses this table for its active/passive validation model
(see `pu:docs/precedence-semiring.md`).

**Binary operators** (used in `BinaryOp` rule):

| Level | Assoc    | Operators                             | Grammar Pattern                           |
|-------|----------|---------------------------------------|-------------------------------------------|
| 0     | right    | `**`                                  | `/\*\*/`                                  |
| 1     | left     | `=~` `!~`                             | `/=~/`, `/!~/`                            |
| 2     | left     | `*` `/` `%` `x`                       | `/[*\/%]/`, `/x\b/`                       |
| 3     | left     | `+` `-` `.`                           | `/[+-]/`, `/\.(?!\.)/`                    |
| 4     | left     | `<<` `>>`                             | `/<</`, `/>>/`                            |
| 5     | nonassoc | `<` `>` `<=` `>=` `lt` `gt` `le` `ge` | `/[<>]=?/`, `/(?:lt\|gt\|le\|ge)\b/`      |
| 6     | chained  | `==` `!=` `<=>` `eq` `ne` `cmp`       | `/[!=]=/`, `/<=>/`, `/(?:eq\|ne\|cmp)\b/` |
| 7     | nonassoc | `isa`                                 | `/isa\b/`                                 |
| 8     | left     | `&`                                   | `/&(?!&)/`                                |
| 9     | left     | `\|` `^`                              | `/\|(?!\|)/`, `/\^/`                      |
| 10    | left     | `&&`                                  | `/&&/`                                    |
| 11    | left     | `\|\|` `//`                           | `/\|\|/`, `/\/\//`                        |
| 12    | nonassoc | `..` `...`                            | `/\.\.\.?/`                               |
| 13    | left     | `and` `or` `xor`                      | `/(?:and\|or\|xor)\b/`                    |

**Non-BinaryOp expression precedence** (relative positioning):

| Precedence | Expression Type                             | Grammar Rule           |
|------------|---------------------------------------------|------------------------|
| Highest    | Postfix (`->`, `[]`, `{}`, `++`, `--`)      | `PostfixExpression`    |
| ↑          | Unary (`!`, `~`, `\`, unary `+`/`-`, `not`) | `UnaryExpression`      |
| ↑          | Binary operators (table above)              | `BinaryExpression`     |
| ↑          | Ternary (`?:`)                              | `TernaryExpression`    |
| ↑          | Assignment (`=`, `+=`, etc.)                | `AssignmentExpression` |
| Lowest     | (expression boundaries)                     |                        |

**Associativity rules** per `pu:docs/precedence-semiring.md`:
- `left`: chains left-to-right (`a + b + c` → `(a+b)+c`)
- `right`: chains right-to-left (`a ** b ** c` → `a**(b**c)`)
- `nonassoc`: cannot chain (`a isa B isa C` is invalid)
- `chained`: can chain in same direction (`a == b == c` valid, `a < b > c` invalid)

### B. Builtin Type Library

Signatures for all Perl builtins used in Chalk source, derived from perldoc.
Feeds the Arity/TypeInference semiring for disambiguation and type validation.

| Builtin   | Arity | Argument Types        | Return Type  | Call Style    |
|-----------|-------|-----------------------|--------------|---------------|
| `bless`   | 2     | (Ref, Str)            | Object       | Parenthesized |
| `defined` | 1     | (Any)                 | Bool         | Both          |
| `delete`  | 1     | (HashElem\|ArrayElem) | Scalar       | Bare          |
| `die`     | 1+    | (Str\|List)           | None (dies)  | Bare          |
| `exists`  | 1     | (HashElem\|ArrayElem) | Bool         | Bare          |
| `grep`    | 2     | (Block, List)         | List         | Block-first   |
| `join`    | 2+    | (Str, List)           | Str          | Parenthesized |
| `keys`    | 1     | (Hash\|HashRef)       | List         | Bare          |
| `last`    | 0     | —                     | Control      | Bare keyword  |
| `length`  | 1     | (Str)                 | Int          | Parenthesized |
| `map`     | 2     | (Block, List)         | List         | Block-first   |
| `next`    | 0     | —                     | Control      | Bare keyword  |
| `ord`     | 1     | (Str)                 | Int          | Parenthesized |
| `pos`     | 1     | (Str)                 | Int (lvalue) | Parenthesized |
| `push`    | 2+    | (Array, List)         | Int          | Bare          |
| `ref`     | 1     | (Any)                 | Str          | Parenthesized |
| `refaddr` | 1     | (Ref)                 | Int          | Parenthesized |
| `return`  | 0-1   | (Any?)                | Control      | Bare keyword  |
| `scalar`  | 1     | (Any)                 | Scalar       | Both          |
| `shift`   | 1     | (Array)               | Scalar       | Bare          |
| `sort`    | 1-2   | (Block?, List)        | List         | Both          |
| `split`   | 2+    | (Regex, Str, Int?)    | List         | Parenthesized |
| `sprintf` | 2+    | (Str, List)           | Str          | Parenthesized |
| `substr`  | 3+    | (Str, Int, Int, Str?) | Str          | Parenthesized |

**Key observation**: Chalk source consistently uses parenthesized calls for
most builtins (`defined($x)`, `ref($x)`, `length($x)`). The exceptions are
`push`, `shift`, `keys`, `sort`, `die`, and loop control (`next`, `last`,
`return`). The Arity/TypeInference semiring may be deferrable if these patterns
don't create genuine ambiguity — same conclusion as the original plan.

-----

## Phase 0: Infrastructure

**Goal**: Wire the 65-rule Perl grammar through the existing BNF pipeline.

**Work**:
- Feed `docs/chalk-bootstrap.bnf` through the existing pipeline:
  desugar → Earley parse → semantic actions → IR → Target::Perl → Generated
- The BNF meta-grammar compiler already handles BNF format; this tests scaling
  (65 rules + quantifier desugaring ≈ 74-79 effective rules vs. the current 10+3)
- Create `Chalk::Grammar::Perl::Generated.pm` — the Perl language recognizer
- Build test harness for progressive grammar subset testing

**Validation**:
- [ ] BNF pipeline accepts `chalk-bootstrap.bnf` without errors
- [ ] Generated recognizer class compiles
- [ ] Performance baseline: time to compile the grammar

**Effort**: Try it and see what breaks. If scaling issues emerge, that's the
signal for Aycock optimizations (`docs/chalk-ayock-optimizations.md`).

-----

## Phase 1: Program Skeleton

**Goal**: Parse empty programs, comments, bare identifiers as statements.

**Grammar rules (10)**:

| Section               | Rules                                       |
|-----------------------|---------------------------------------------|
| §1 Whitespace         | `_`, `WS`                                   |
| §2 Structure          | `Program`, `StatementList`, `StatementItem` |
| §3 Categories         | `SimpleStatement`, `CompoundStatement`      |
| §4 Expr Stmt          | `ExpressionStatement`                       |
| §12 Expr (partial)    | `Expression` → `Atom` only                  |
| §13 Atoms (partial)   | `Atom` → `Identifier` only                  |
| §20 Helpers (partial) | `Identifier`, `Block`                       |

**Test data**:
```perl
""                          # empty program
";"                         # empty statement
";;"                        # multiple empty statements
"# a comment\n"             # comment-only program
"foo;"                      # identifier as expression
"foo; bar; baz;"            # multiple statements
"{ foo; }"                  # block as compound statement
```

**Validation**:
- [ ] All test inputs accepted by generated recognizer
- [ ] Invalid inputs rejected (e.g., unclosed `{`)
- [ ] Performance: grammar compiles in reasonable time

-----

## Phase 2: Declarations and Literals

**Goal**: Parse `use` declarations, variable declarations, field declarations,
and literal values.

**Grammar rules added (22, total ~32)**:

| Section              | Rules                                                                                            |
|----------------------|--------------------------------------------------------------------------------------------------|
| §7 Use               | `UseDeclaration`, `ModuleName`, `ImportList`                                                     |
| §8 Var/Field         | `VariableDeclaration`, `VariableList`, `FieldDeclaration`, `DefaultValue`                        |
| §12 Expr (extend)    | `ExpressionList`                                                                                 |
| §13 Atoms (extend)   | `Atom` += `Variable`, `Literal`, `ParenExpr`, `QwLiteral`, `ArrayConstructor`, `HashConstructor` |
| §18 Variables        | `Variable`, `ScalarVariable`, `ArrayVariable`, `HashVariable`                                    |
| §19 Literals         | `Literal`, `NumericLiteral`, `StringLiteral`, `RegexLiteral`                                     |
| §20 Helpers (extend) | `QualifiedIdentifier`, `Version`                                                                 |

**Test data**:
```perl
"use 5.42.0;"                              # version pragma
"use utf8;"                                # module use
"use experimental 'class';"                # use with import list
"use experimental qw(class builtin);"      # use with qw()
"my $x;"                                   # bare variable declaration
"my $x = 42;"                              # variable with initializer
"my ($x, $y) = (1, 2);"                   # list variable declaration
"our @EXPORT_OK = ('foo', 'bar');"         # array declaration
"state %cache;"                            # state hash
"'hello';"                                 # single-quoted string
"42;"                                      # numeric literal
"0xFF;"                                    # hex literal
"3.14;"                                    # float literal
"/pattern/;"                               # regex literal
"undef;"                                   # undef literal
"true;"                                    # boolean literal
"[1, 2, 3];"                              # array constructor
```

**ConciseTree validation**: Begin validating simple statements against
`perl -MO=Concise` output. `use 5.42.0;` and `my $x = 42;` have trivial
optrees that serve as baseline comparisons.

**Validation**:
- [ ] All test inputs accepted
- [ ] ConciseTree output matches B::Concise for simple declarations
- [ ] Quantifier desugaring handles `?` in `StatementList?`, `DefaultValue?`, etc.

-----

## Phase 3: Class Definitions

**Goal**: Parse class/sub/method definitions with attributes and signatures.

**Grammar rules added (13, total ~45)**:

| Section            | Rules                                                                                            |
|--------------------|--------------------------------------------------------------------------------------------------|
| §9 Definitions     | `ClassBlock`, `SubroutineDefinition`, `MethodDefinition`, `AdjustBlock`                          |
| §10 Attributes     | `AttributeList`, `Attribute`                                                                     |
| §11 Signatures     | `Signature`, `SignatureParams`, `SignatureParam`, `ScalarSignatureParam`, `SlurpySignatureParam` |
| §13 Atoms (extend) | `Atom` += `AnonymousSub`                                                                         |

**Test data**:
```perl
# Minimal class
"class Foo { }"

# Class with inheritance
"class Foo :isa(Bar) { }"

# Class with fields
"class Foo {
    field $x :param :reader;
    field $y :param = undef;
}"

# Class with method
"class Foo {
    field $x :param;
    method name() { }
}"

# Method with signature
"method process($input, $output) { }"

# Method with optional param
"method lookup($key, $default = undef) { }"

# Method with slurpy
"method collect(@items) { }"
"method configure(%opts) { }"

# Subroutine definition
"sub helper($arg) { }"

# Lexical sub
"my sub _private($x) { }"

# ADJUST block
"class Foo { ADJUST { } }"

# Full class combining everything
"class Foo :isa(Bar) {
    field $name :param :reader;
    field $count :param = 0;
    method increment() { }
    ADJUST { }
}"
```

**Validation**:
- [ ] All test inputs accepted
- [ ] Attribute lists parse correctly (`:param :reader`, `:isa(Foo::Bar)`)
- [ ] Trailing comma in signatures accepted (`$x, $y,`)
- [ ] ConciseTree for class structures matches B::Concise

-----

## Phase 4: Expressions (Ambiguity Frontier)

**Goal**: Parse all expression types. This is where ambiguity explodes and
disambiguation semirings become necessary.

**Grammar rules added (14, total ~59)**:

| Section               | Rules                                                                                             |
|-----------------------|---------------------------------------------------------------------------------------------------|
| §4 Expr Stmt (extend) | `PostfixModifier`                                                                                 |
| §12 Expr (extend)     | `Expression` += all alternatives                                                                  |
| §14 Unary             | `UnaryExpression`                                                                                 |
| §15 Binary            | `BinaryExpression`, `BinaryOp`                                                                    |
| §16 Postfix           | `PostfixExpression`, `MethodCall`, `Subscript`, `PostfixDeref`, `CallExpression`, `PostfixIncDec` |
| §17 Ternary/Assign    | `TernaryExpression`, `AssignmentExpression`, `AssignOp`                                           |

**Requires before this phase**:

1. **Precedence semiring** — The flat `BinaryExpression ::= Expression _ BinaryOp _ Expression`
   rule produces an exponential number of parses without it. Build using the
   active/passive model from `pu:docs/precedence-semiring.md` with the precedence
   table from Section A above.

2. **Structural semiring** — `HashConstructor` (`{ ExpressionList? }`) and `Block`
   (`{ StatementList? }`) both match `{ ... }`. The Structural semiring resolves
   this using syntactic context: after `=`, `=>`, `,`, `(` → hash constructor;
   after `if`, `while`, `class`, `method`, `sub` → block.

3. **ChalkSyntax composition** — Wire Boolean + Precedence + Structural into a
   Composite semiring with staged-filter `add()`.

**Test data**:
```perl
# Binary expressions — precedence
"$a + $b * $c;"                 # must parse as $a + ($b * $c)
"$a * $b + $c;"                 # must parse as ($a * $b) + $c
"$a ** $b ** $c;"               # must parse as $a ** ($b ** $c) (right-assoc)
"$a + $b + $c;"                 # must parse as ($a + $b) + $c (left-assoc)
"$a && $b || $c;"               # must parse as ($a && $b) || $c

# Parentheses override precedence
"($a + $b) * $c;"

# Unary expressions
"!$x;"
"-$x;"
"\\@array;"                     # reference constructor
"not $x;"

# Method calls
"$obj->method();"
"$obj->method;"                 # no-arg method call
"$obj->method($a, $b);"
"$class->new(name => 'foo');"

# Subscripts
"$array->[$i];"
"$hash->{$key};"
"$ref->($arg);"                 # coderef call
"$arr[$i];"                     # direct subscript

# Postfix deref
"$ref->@*;"
"$ref->%*;"

# Call expressions
"defined($x);"
"push $arr->@*, $val;"
"map { $_ * 2 } @list;"
"grep { defined } @items;"
"join(', ', @parts);"

# Ternary
"$x ? $y : $z;"

# Assignment
"$x = 1;"
"$x += 1;"
"$x //= $default;"

# Postfix modifiers
"return $x if $cond;"
"push @arr, $val for @items;"
"next unless defined($x);"

# Postfix inc/dec
"$x++;"

# Block vs hash disambiguation (Structural semiring)
"{ $x => $y };"                 # hash constructor
"if ($x) { $y; }"              # block (when control flow added)

# Comparison operators
"$a == $b;"
"$a eq $b;"
"$a <=> $b;"
"$obj isa Foo::Bar;"

# String operators
"$a . $b;"
"$a x 3;"

# Regex binding
"$str =~ /pattern/;"

# Defined-or
"$x // $default;"

# Range
"1 .. 10;"
```

**ConciseTree validation**: This is where ConciseTree becomes essential. Compare
structural output against B::Concise for expression trees. Verify:
- Same set of operations appears
- Data dependencies are consistent
- Control flow shape matches

**Validation**:
- [ ] All test inputs accepted with exactly one parse (after disambiguation)
- [ ] Precedence semiring correctly resolves operator binding
- [ ] Structural semiring correctly resolves block/hash ambiguity
- [ ] ConciseTree matches B::Concise for expression structures
- [ ] Performance acceptable (if not, begin Aycock optimizations)

-----

## Phase 5: Control Flow + Full Grammar

**Goal**: Complete the grammar with conditionals and loops. Parse actual `.pm` files.

**Grammar rules added (6, total 65)**:

| Section         | Rules                                                                    |
|-----------------|--------------------------------------------------------------------------|
| §5 Conditionals | `IfStatement`, `ElsifChain`                                              |
| §6 Loops        | `WhileStatement`, `ForStatement`, `ForeachStatement`, `IteratorVariable` |

**Test data**:
```perl
# If/elsif/else
"if ($x) { }"
"if ($x) { } else { }"
"if ($x) { } elsif ($y) { } else { }"
"unless ($done) { }"

# While/until
"while ($cond) { }"
"until ($done) { }"

# C-style for
"for (my $i = 0; $i < 10; $i++) { }"

# Foreach
"for my $item (@list) { }"
"foreach my $key (keys %hash) { }"
"for (@list) { }"

# Combined: full program structures
"use 5.42.0;
use utf8;

class Foo :isa(Bar) {
    field $name :param :reader;
    field $count :param = 0;

    method increment() {
        $count++;
    }

    method process($input) {
        if (defined($input)) {
            return $input;
        }
        return undef;
    }

    method collect(@items) {
        my @results;
        for my $item (@items) {
            push @results, $item
                if defined($item);
        }
        return \\@results;
    }
}"
```

**Full file recognition**: After synthetic tests pass, test against every `.pm`
file under `lib/Chalk/`. This is the first time the recognizer touches real code.

**Validation**:
- [ ] All synthetic test inputs accepted
- [ ] All `.pm` files under `lib/Chalk/` recognized (accepted by the parser)
- [ ] ConciseTree validation for control flow structures
- [ ] Performance: full-file recognition completes in acceptable time
- [ ] If performance issues: implement Aycock optimizations per `docs/chalk-ayock-optimizations.md`

-----

## Phases 6-8: Tier-Driven Compilation

These phases compile actual Chalk source files end-to-end, organized by
**tier** (vertical slices) rather than by phase (horizontal slices). Each tier
takes its files through all three stages — IR, Perl lowering, XS lowering —
before the next tier begins.

### Why Tier-First

The original plan organized Phases 6-8 as horizontal slices: build IR for all
files, then lower all to Perl, then lower all to XS. The tier-first approach
has several advantages:

1. **Earlier end-to-end validation.** IR design problems that prevent clean
   lowering surface after 4 files, not 37.
2. **Working software sooner.** After Tier A, 4 files go from parse to XS.
3. **Incremental IR design.** IR node types grow organically as each tier
   introduces new constructs, rather than being designed up-front.
4. **Cheaper rework.** If lowering reveals IR issues, fewer files need fixing.
5. **Natural commit boundaries.** Each tier is a coherent deliverable.

### File Tiers

Tiers follow the validated ordering from `concise-per-file.t` (37/37 oracle
match). Files are listed by their `lib/Chalk/Bootstrap/` or `lib/Chalk/`
relative path.

**Tier A — Pure data classes (4 files)**:
Simplest files: `use` declarations, `feature class`, methods returning string
constants. All constructs already have ConciseTree action methods.

| # | File                | Key Constructs          |
|---|---------------------|-------------------------|
| 1 | `IR/Node/Start.pm`  | :isa, 1 override method |
| 2 | `IR/Node/Return.pm` | :isa, 1 override method |
| 3 | `Target.pm`         | Abstract interface, die |
| 4 | `Optimizer/Pass.pm` | Abstract base, die      |

**Tier B — Classes with field declarations (5 files)**:
Same as Tier A but with `field` declarations, which cause B::Concise to emit
nextstate instead of stub inside the class body.

| # | File                         | Key Constructs                 |
|---|------------------------------|--------------------------------|
| 5 | `IR/Node/Constant.pm`        | :isa, 2 fields, override       |
| 6 | `Target/XS/AST/Node.pm`      | Abstract interface, die        |
| 7 | `Target/XS/AST/Statement.pm` | 1 field, string interpolation  |
| 8 | `Target/XS/AST/Module.pm`    | 2 fields, string interpolation |
| 9 | `IR/Node/Constructor.pm`     | :isa, 1 field, override        |

**Tier C — Classes with runtime method logic (5 files)**:
Methods use string interpolation, conditionals, regex, join, push, etc.
B::Concise sees compile-time class envelope only for main program.

| #  | File                        | Key Constructs                   |
|----|-----------------------------|----------------------------------|
| 10 | `ConciseOp.pm`              | Methods with regex, conditionals |
| 11 | `ConciseTree.pm`            | Multi-method class               |
| 12 | `ConciseTree/Comparator.pm` | Regex substitution, conditionals |
| 13 | `ConciseTree/Oracle.pm`     | Process execution, parsing       |
| 14 | `Context.pm`                | 4 fields, recursion, push        |

**Tier D — All remaining files (23 files)**:
Diverse method bodies, standalone modules with subs, and large files.

| #  | File                              | Key Constructs                                 |
|----|-----------------------------------|------------------------------------------------|
| 15 | `Target/XS/AST/CompositeNode.pm`  | 1 field, map + join                            |
| 16 | `Target/XS/AST/VarDecl.pm`        | 2 fields, regex, ternary                       |
| 17 | `Grammar/Symbol.pm`               | 3 fields, 3 readers, defined                   |
| 18 | `Target/XS/AST/Preamble.pm`       | Multi-line string constant                     |
| 19 | `Terminal.pm`                     | Static method, regex, pos(), length()          |
| 20 | `Grammar/Rule.pm`                 | Nested loops, map, join, scalar                |
| 21 | `IR/Node.pm`                      | Base class, refaddr, grep, push, postfix deref |
| 22 | `Optimizer.pm`                    | Type checking (isa), push, die                 |
| 23 | `Semiring/Composite.pm`           | 2 fields, delegation pattern                   |
| 24 | `Semiring/SemanticAction.pm`      | Context threading, can() dispatch              |
| 25 | `Grammar/Perl/KeywordTable.pm`    | Hash lookup table, exists                      |
| 26 | `Target/XS/AST/XSUB.pm`           | 4 fields, split, map, push, join               |
| 27 | `Optimizer/DCE.pm`                | Mark-sweep graph traversal, worklist           |
| 28 | `Target/Perl.pm`                  | Recursive emit, regex escaping, map            |
| 29 | `Grammar/BNF/Generated.pm`        | Auto-generated, same shape as BNF.pm           |
| 30 | `Desugar.pm`                      | Quantifier transform, exists, sort keys        |
| 31 | `Grammar/BNF.pm`                  | Complex data construction, 10 rules            |
| 32 | `Semiring/Structural.pm`          | Block/hash disambiguation                      |
| 33 | `Semiring/TypeInference.pm`       | Keyword rejection, tag propagation             |
| 34 | `Earley.pm`                       | State machine, chart parsing, regex, substr    |
| 35 | `Target/XS.pm`                    | XS generation, ord, sprintf, s///ge            |
| 36 | `Grammar/Perl/PrecedenceTable.pm` | Operator precedence lookup table               |
| 37 | `Semiring/Boolean.pm`             | bless, refaddr, reference equality             |

**Not yet in per-file oracle (4 files)** — these will be added to a tier
once their ConciseTree actions stabilize:

| File                     | Key Constructs                            |
|--------------------------|-------------------------------------------|
| `Semiring/Precedence.pm` | Precedence validation, lookup dispatch    |
| `IR/NodeFactory.pm`      | Hash consing, delete, ref, die, sort      |
| `Grammar/BNF/Actions.pm` | 12 methods, tree traversal, type dispatch |
| `ConciseTree/Actions.pm` | 1505 lines, 40+ action methods            |

### Per-Tier Work

Each tier performs three stages end-to-end before the next tier begins.

#### Stage 1: Perl IR (corresponds to Phase 6)

**Goal**: Parse each file and produce a Perl-domain IR (Sea of Nodes or
similar structured representation).

**Work**:
- Design Perl IR node types as needed (extend from previous tiers)
- Build SemanticAction callbacks for Perl grammar rules as needed
- ConciseTree validation: compare IR structure against B::Concise

**Validation per file**:
- [ ] File parses completely (no unparsed trailing input)
- [ ] IR is well-formed (no dangling references)
- [ ] ConciseTree output matches B::Concise structurally

#### Stage 2: Lower to Perl (corresponds to Phase 7)

**Goal**: Generate Perl source from IR. Validate generated code matches
existing source (diff-able or behaviorally equivalent).

**Work**:
- Build `Target::Perl` for Perl-domain IR (extend from previous tiers)
- Compare generated output against original source

**Validation per file**:
- [ ] Generated Perl compiles without errors
- [ ] Generated code passes same tests as original
- [ ] Structural comparison: same methods, fields, class hierarchy

#### Stage 3: Lower to XS (corresponds to Phase 8)

**Goal**: Generate XS/C from IR. Validate XS is functionally equivalent
to existing Perl source.

**Work**:
- Build `Target::XS` for Perl-domain IR (extend from previous tiers)
- Compile generated XS with `perl Build.PL && ./Build`

**Validation per file**:
- [ ] Generated XS compiles without errors
- [ ] Tests pass — XS modules are functionally equivalent to Perl originals

### Tier-Specific Notes

**Tier A** establishes the foundational IR type system and lowering patterns.
These 4 files are pure data classes — the simplest possible end-to-end path.
The IR node types, Target::Perl, and Target::XS created here form the base
that subsequent tiers extend.

**Tier B** adds `field` declarations and string interpolation. The IR gains
field-related node types. Lowering must handle interpolated strings.

**Tier C** adds runtime method logic: conditionals, regex, recursion, push.
The IR gains control flow and builtin call node types. This tier is where
lowering complexity jumps significantly.

**Tier D** is the long tail — 23 files with diverse constructs. Tier A-C
should have established all the infrastructure; Tier D is primarily exercising
it across varied patterns. Files with unusual constructs (hash consing in
NodeFactory, state machine in Earley, s///ge in Target::XS) may require
targeted IR extensions.

-----

## Phase 9: Optimizations

**Goal**: Same correctness, better performance.

**Work**:
- **Peephole optimization**: Constant folding, algebraic simplification
  (per `pu:docs/chalk-ir-type-mapping.md` IR type system)
- **GCM (Global Code Motion)**: Hoist/sink loop-invariant computations
- **Aycock parser optimizations**: If not already implemented during Phases 1-5,
  implement the techniques from `docs/chalk-ayock-optimizations.md`:
  - CoreItemIndex + bitmap membership
  - LR(0) DFA construction + predict_via_dfa
  - Safe-set chart GC
  - Terminal clustering
  - Lazy semiring init
  - Earley set compression

**Validation**:
- [ ] All existing tests still pass (optimization preserves correctness)
- [ ] Measurable performance improvement on full-file parsing
- [ ] Measurable performance improvement on generated code execution

-----

## Cumulative Summary

| Phase      | Description                    | New Infrastructure                                 | Key Deliverable                      |
|------------|--------------------------------|----------------------------------------------------|--------------------------------------|
| 0          | Infrastructure                 | —                                                  | Perl grammar through BNF pipeline    |
| 1          | Program skeleton               | —                                                  | 10-rule subset recognizer            |
| 2          | Declarations + literals        | ConciseTree semiring                               | Parses `use`, `my`, literals         |
| 3          | Class definitions              | —                                                  | Parses class/method/field            |
| 4          | Expressions                    | **Precedence + Structural semirings**, ChalkSyntax | Disambiguated expression parsing     |
| 5          | Control flow + full grammar    | TypeInference semiring                             | All 37 .pm files recognized          |
| 6-8 Tier A | Pure data classes (4 files)    | Perl IR node types, Target::Perl, Target::XS       | End-to-end IR → Perl → XS            |
| 6-8 Tier B | Field declarations (5 files)   | Field IR nodes                                     | Interpolation + fields lowered       |
| 6-8 Tier C | Runtime method logic (5 files) | Control flow + builtin IR nodes                    | Conditionals + regex lowered         |
| 6-8 Tier D | All remaining (23 files)       | Targeted IR extensions                             | Full self-hosting compilation        |
| 9          | Optimizations                  | Peephole, GCM, Aycock                              | Same correctness, better performance |

-----

## Decision Log

**Arity/TypeInference semiring: Initially deferred, implemented during Phase 4**

Initial reasoning: Chalk source consistently uses parenthesized builtin
calls (`defined($x)`, `ref($x)`, `length($x)`), with no bare `time + 1` style
ambiguity. Exceptions (`push`, `shift`, `keys`, `die`) use postfix deref or
have unambiguous context. The plan was to build TypeInference only if Phase 5
full-file recognition revealed actual ambiguity.

Outcome: the ambiguity surfaced earlier than expected — during Phase 4
expression parsing, not Phase 5. Three drivers converged: regex-vs-division
disambiguation (`/pattern/` vs division), fat-arrow type assertion (`class =>
"Foo"` casts the LHS to String, so keyword-starting rules can be rejected),
and keyword rejection in concrete syntax (blocking `concise-actions.t` test
29 on `use 5.42.0`). TypeInference is now live as one of the five
FilterComposite semirings. See `docs/architecture/parsing-pipeline.md` and
`docs/plans/2026-02-20-typeinference-redesign.md`.

**Structural semiring: Needed at Phase 4**

First `HashConstructor` / `Block` collision occurs when both
`{ ExpressionList? }` and `{ StatementList? }` are in the grammar. Simple
context heuristic: contains `=>` or follows `=`/`,`/`(` → hash; follows keyword → block.

**ConciseTree semiring: Introduced at Phase 2**

Early introduction (simple statements) establishes the validation pattern before
expression complexity arrives. The oracle is most valuable at Phase 4+ where
structural correctness of expression trees matters.

**Aycock optimizations: ON DEMAND**

Not built speculatively. If Phase 0 grammar compilation is slow, or Phase 4-5
expression parsing causes performance issues, that's the trigger. The existing
Earley parser should handle 65 rules; if it doesn't, measure first, then
implement the highest-bang-for-buck optimization from the Aycock doc.

**File ordering: Tier-first (vertical slices) for Phases 6-8**

Each tier takes its files through IR → Perl → XS end-to-end before the next
tier begins. This replaced the original horizontal-slice approach (all IR,
then all Perl, then all XS) because it provides earlier end-to-end validation,
incremental IR design, cheaper rework, and natural commit boundaries. Tier
membership follows the validated ordering from `concise-per-file.t`.

**String interpolation: OPAQUE**

`"$var"` and `"text $var more"` matched as opaque string literals by the
`StringLiteral` terminal pattern. No interpolation sub-grammar. XS backend
emits them as Perl double-quoted strings, letting the runtime handle interpolation.
