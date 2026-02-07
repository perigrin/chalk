# Chalk Self-Hosting: Bootstrap Branch Roadmap

## Strategy

Extend the existing BNF-to-Perl bootstrap pipeline to parse Perl 5.42.0 source
code, ultimately self-hosting by compiling the ~31 `.pm` files under `lib/Chalk/`.

The approach has two major stages:

1. **Progressive grammar recognition (Phases 1-5)**: Feed increasingly larger
   subsets of the 65-rule Perl grammar (`docs/chalk-bootstrap.bnf`) through the
   existing BNF pipeline. Use synthetic test inputs. Add disambiguation semirings
   and Aycock parser optimizations as needed — not before.

2. **File-driven compilation (Phases 6-8)**: Walk through actual bootstrap source
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

Two composite semirings, following the pattern established in mainline Chalk:

**ChalkSyntax** — The disambiguating recognizer:

```
ChalkSyntax = Composite(Boolean, Precedence, Structural, [Arity/TypeInference])
```

Produces exactly ONE unambiguous parse. All disambiguation happens during the
parse via `add()`. No post-parse filtering.

**ChalkIR** (name TBD) — Layers IR construction on top:

```
ChalkIR = Composite(ChalkSyntax, SemanticAction)
```

ChalkSyntax MUST produce one unambiguous parse before SemanticAction generates
IR. This is the cardinal rule from `docs/semiring-architecture.md`.

### Staged Filter in `add()`

When two alternative parses meet at the same chart item, ChalkSyntax's `add()`
consults component semirings as a staged filter with short-circuit rejection:

```
Boolean     → reject? done (cheapest check)
Precedence  → reject? done
Structural  → reject? done
TypeInfer   → reject? done (most expensive)
keep the survivor
```

The semirings are order-agnostic for correctness — each independently votes
valid/invalid. The ordering is purely a performance concern (cheapest/most-
discriminating filters first). This can be tuned later via profiling.

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

| Document | Location | Relevance |
|---|---|---|
| Semiring Architecture | `pu:docs/semiring-architecture.md` | Cardinal rule: one parse before IR |
| Precedence Semiring | `pu:docs/precedence-semiring.md` | Active/passive model, table-driven design |
| Type System (Grammar) | `pu:docs/chalk-grammar-types.md` | Type lattice: Int <: Num <: Str <: Scalar |
| Type Mapping (IR) | `pu:docs/chalk-ir-type-mapping.md` | Grammar ↔ IR type bridge |
| Perl Types (Practical) | `pu:docs/perl-types-practical.md` | Round-trip + behavioral membership tests |
| Aycock Optimizations | `docs/chalk-ayock-optimizations.md` | Parser performance techniques |
| Perl Grammar Spec | `docs/perlish-grammar-spec.md` | 65-rule grammar, 20 sections |
| BNF Grammar File | `docs/chalk-bootstrap.bnf` | Machine-readable grammar |

-----

## Concrete Deliverables

### A. Perl Operator Precedence Table

Derived from perlop. Lower level number = higher precedence (binds tighter).
The Precedence semiring uses this table for its active/passive validation model
(see `pu:docs/precedence-semiring.md`).

**Binary operators** (used in `BinaryOp` rule):

| Level | Assoc | Operators | Grammar Pattern |
|-------|-------|-----------|-----------------|
| 0 | right | `**` | `/\*\*/` |
| 1 | left | `=~` `!~` | `/=~/`, `/!~/` |
| 2 | left | `*` `/` `%` `x` | `/[*\/%]/`, `/x\b/` |
| 3 | left | `+` `-` `.` | `/[+-]/`, `/\.(?!\.)/` |
| 4 | left | `<<` `>>` | `/<</`, `/>>/` |
| 5 | nonassoc | `<` `>` `<=` `>=` `lt` `gt` `le` `ge` | `/[<>]=?/`, `/(?:lt\|gt\|le\|ge)\b/` |
| 6 | chained | `==` `!=` `<=>` `eq` `ne` `cmp` | `/[!=]=/`, `/<=>/`, `/(?:eq\|ne\|cmp)\b/` |
| 7 | nonassoc | `isa` | `/isa\b/` |
| 8 | left | `&` | `/&(?!&)/` |
| 9 | left | `\|` `^` | `/\|(?!\|)/`, `/\^/` |
| 10 | left | `&&` | `/&&/` |
| 11 | left | `\|\|` `//` | `/\|\|/`, `/\/\//` |
| 12 | nonassoc | `..` `...` | `/\.\.\.?/` |
| 13 | left | `and` `or` `xor` | `/(?:and\|or\|xor)\b/` |

**Non-BinaryOp expression precedence** (relative positioning):

| Precedence | Expression Type | Grammar Rule |
|---|---|---|
| Highest | Postfix (`->`, `[]`, `{}`, `++`, `--`) | `PostfixExpression` |
| ↑ | Unary (`!`, `~`, `\`, unary `+`/`-`, `not`) | `UnaryExpression` |
| ↑ | Binary operators (table above) | `BinaryExpression` |
| ↑ | Ternary (`?:`) | `TernaryExpression` |
| ↑ | Assignment (`=`, `+=`, etc.) | `AssignmentExpression` |
| Lowest | (expression boundaries) | |

**Associativity rules** per `pu:docs/precedence-semiring.md`:
- `left`: chains left-to-right (`a + b + c` → `(a+b)+c`)
- `right`: chains right-to-left (`a ** b ** c` → `a**(b**c)`)
- `nonassoc`: cannot chain (`a isa B isa C` is invalid)
- `chained`: can chain in same direction (`a == b == c` valid, `a < b > c` invalid)

### B. Builtin Type Library

Signatures for all Perl builtins used in bootstrap source, derived from perldoc.
Feeds the Arity/TypeInference semiring for disambiguation and type validation.

| Builtin | Arity | Argument Types | Return Type | Call Style |
|---------|-------|---------------|-------------|------------|
| `bless` | 2 | (Ref, Str) | Object | Parenthesized |
| `defined` | 1 | (Any) | Bool | Both |
| `delete` | 1 | (HashElem\|ArrayElem) | Scalar | Bare |
| `die` | 1+ | (Str\|List) | None (dies) | Bare |
| `exists` | 1 | (HashElem\|ArrayElem) | Bool | Bare |
| `grep` | 2 | (Block, List) | List | Block-first |
| `join` | 2+ | (Str, List) | Str | Parenthesized |
| `keys` | 1 | (Hash\|HashRef) | List | Bare |
| `last` | 0 | — | Control | Bare keyword |
| `length` | 1 | (Str) | Int | Parenthesized |
| `map` | 2 | (Block, List) | List | Block-first |
| `next` | 0 | — | Control | Bare keyword |
| `ord` | 1 | (Str) | Int | Parenthesized |
| `pos` | 1 | (Str) | Int (lvalue) | Parenthesized |
| `push` | 2+ | (Array, List) | Int | Bare |
| `ref` | 1 | (Any) | Str | Parenthesized |
| `refaddr` | 1 | (Ref) | Int | Parenthesized |
| `return` | 0-1 | (Any?) | Control | Bare keyword |
| `scalar` | 1 | (Any) | Scalar | Both |
| `shift` | 1 | (Array) | Scalar | Bare |
| `sort` | 1-2 | (Block?, List) | List | Both |
| `split` | 2+ | (Regex, Str, Int?) | List | Parenthesized |
| `sprintf` | 2+ | (Str, List) | Str | Parenthesized |
| `substr` | 3+ | (Str, Int, Int, Str?) | Str | Parenthesized |

**Key observation**: Bootstrap source consistently uses parenthesized calls for
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

| Section | Rules |
|---------|-------|
| §1 Whitespace | `_`, `WS` |
| §2 Structure | `Program`, `StatementList`, `StatementItem` |
| §3 Categories | `SimpleStatement`, `CompoundStatement` |
| §4 Expr Stmt | `ExpressionStatement` |
| §12 Expr (partial) | `Expression` → `Atom` only |
| §13 Atoms (partial) | `Atom` → `Identifier` only |
| §20 Helpers (partial) | `Identifier`, `Block` |

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

| Section | Rules |
|---------|-------|
| §7 Use | `UseDeclaration`, `ModuleName`, `ImportList` |
| §8 Var/Field | `VariableDeclaration`, `VariableList`, `FieldDeclaration`, `DefaultValue` |
| §12 Expr (extend) | `ExpressionList` |
| §13 Atoms (extend) | `Atom` += `Variable`, `Literal`, `ParenExpr`, `QwLiteral`, `ArrayConstructor`, `HashConstructor` |
| §18 Variables | `Variable`, `ScalarVariable`, `ArrayVariable`, `HashVariable` |
| §19 Literals | `Literal`, `NumericLiteral`, `StringLiteral`, `RegexLiteral` |
| §20 Helpers (extend) | `QualifiedIdentifier`, `Version` |

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

| Section | Rules |
|---------|-------|
| §9 Definitions | `ClassBlock`, `SubroutineDefinition`, `MethodDefinition`, `AdjustBlock` |
| §10 Attributes | `AttributeList`, `Attribute` |
| §11 Signatures | `Signature`, `SignatureParams`, `SignatureParam`, `ScalarSignatureParam`, `SlurpySignatureParam` |
| §13 Atoms (extend) | `Atom` += `AnonymousSub` |

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

| Section | Rules |
|---------|-------|
| §4 Expr Stmt (extend) | `PostfixModifier` |
| §12 Expr (extend) | `Expression` += all alternatives |
| §14 Unary | `UnaryExpression` |
| §15 Binary | `BinaryExpression`, `BinaryOp` |
| §16 Postfix | `PostfixExpression`, `MethodCall`, `Subscript`, `PostfixDeref`, `CallExpression`, `PostfixIncDec` |
| §17 Ternary/Assign | `TernaryExpression`, `AssignmentExpression`, `AssignOp` |

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

| Section | Rules |
|---------|-------|
| §5 Conditionals | `IfStatement`, `ElsifChain` |
| §6 Loops | `WhileStatement`, `ForStatement`, `ForeachStatement`, `IteratorVariable` |

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
- [ ] All 31 `.pm` files under `lib/Chalk/` recognized (accepted by the parser)
- [ ] ConciseTree validation for control flow structures
- [ ] Performance: full-file recognition completes in acceptable time
- [ ] If performance issues: implement Aycock optimizations per `docs/chalk-ayock-optimizations.md`

-----

## Phases 6-8: File-Driven Compilation

These phases walk through actual bootstrap source files from least complex to
most complex. The same file ordering is used for all three phases.

### File Ordering (Least to Most Complex)

**Tier A — Pure data classes and minimal interfaces (11 files)**:

| # | File | Lines | Key Constructs |
|---|------|-------|----------------|
| 1 | `Target/XS/AST/Node.pm` | 11 | Abstract interface, die |
| 2 | `Optimizer/Pass.pm` | 15 | Abstract base, die |
| 3 | `Grammar/Symbol.pm` | 21 | 3 fields, 3 readers, defined |
| 4 | `Target.pm` | 15 | Abstract interface, die |
| 5 | `IR/Node/Start.pm` | 11 | :isa, 1 override method |
| 6 | `IR/Node/Return.pm` | 11 | :isa, 1 override method |
| 7 | `Terminal.pm` | 24 | Static method, regex, pos(), length() |
| 8 | `Target/XS/AST/Module.pm` | 16 | 2 fields, string interpolation |
| 9 | `Target/XS/AST/CompositeNode.pm` | 15 | 1 field, map + join |
| 10 | `Target/XS/AST/Statement.pm` | 15 | 1 field, string interpolation |
| 11 | `Target/XS/AST/VarDecl.pm` | 18 | 2 fields, regex, ternary |

**Tier B — Moderate logic, simple control flow (9 files)**:

| # | File | Lines | Key Constructs |
|---|------|-------|----------------|
| 12 | `Grammar/Rule.pm` | 32 | Nested loops, map, join, scalar |
| 13 | `IR/Node/Constant.pm` | 17 | :isa, 2 fields, override |
| 14 | `IR/Node/Constructor.pm` | 15 | :isa, 1 field, override |
| 15 | `Semiring/Boolean.pm` | 54 | bless, refaddr, reference equality |
| 16 | `Context.pm` | 76 | 4 fields, recursion, push |
| 17 | `Optimizer.pm` | 34 | Type checking (isa), push, die |
| 18 | `Semiring/Composite.pm` | 51 | 2 fields, delegation pattern |
| 19 | `Target/XS/AST/Preamble.pm` | 24 | Multi-line string constant |
| 20 | `Semiring/SemanticAction.pm` | 97 | Context threading, can() dispatch |

**Tier C — Complex multi-method logic (6 files)**:

| # | File | Lines | Key Constructs |
|---|------|-------|----------------|
| 21 | `Grammar/BNF.pm` | 135 | Complex data construction, 10 rules |
| 22 | `Grammar/BNF/Generated.pm` | 124 | Auto-generated, same shape as BNF.pm |
| 23 | `IR/NodeFactory.pm` | 162 | Hash consing, delete, ref, die, sort |
| 24 | `Desugar.pm` | 131 | Quantifier transform, exists, sort keys |
| 25 | `Target/XS/AST/XSUB.pm` | 64 | 4 fields, split, map, push, join |
| 26 | `Target/Perl.pm` | 124 | Recursive emit, regex escaping, map |

**Tier D — Most complex implementations (5 files)**:

| # | File | Lines | Key Constructs |
|---|------|-------|----------------|
| 27 | `IR/Node.pm` | 42 | Base class, refaddr, grep, push, postfix deref |
| 28 | `Grammar/BNF/Actions.pm` | 263 | 12 methods, tree traversal, type dispatch |
| 29 | `Earley.pm` | 249 | State machine, chart parsing, regex, substr |
| 30 | `Optimizer/DCE.pm` | 76 | Mark-sweep graph traversal, worklist |
| 31 | `Target/XS.pm` | 304 | XS generation, ord, sprintf, s///ge |

### Phase 6: Perl IR

**Goal**: Parse each bootstrap source file and produce a Perl-domain IR
(Sea of Nodes or similar structured representation).

**Work**:
- Design Perl IR node types (distinct from BNF IR nodes)
- Build SemanticAction callbacks for Perl grammar rules
- Walk files in order above, building IR for each
- ConciseTree validation: compare IR structure against B::Concise

**Validation per file**:
- [ ] File parses completely (no unparsed trailing input)
- [ ] IR is well-formed (no dangling references)
- [ ] ConciseTree output matches B::Concise structurally

### Phase 7: Lower to Perl

**Goal**: Generate Perl source from IR. Validate generated code matches
existing source (diff-able or behaviorally equivalent).

**Work**:
- Build `Target::Perl` for Perl-domain IR (analogous to existing BNF Target::Perl)
- Walk files in same order
- Compare generated output against original source

**Validation per file**:
- [ ] Generated Perl compiles without errors
- [ ] Generated code passes same tests as original
- [ ] Structural comparison: same methods, fields, class hierarchy

### Phase 8: Lower to XS

**Goal**: Generate XS/C from IR. Validate XS is functionally equivalent
to existing Perl source.

**Work**:
- Build `Target::XS` for Perl-domain IR
- Walk files in same order
- Compile generated XS with `perl Makefile.PL && make`

**Validation per file**:
- [ ] Generated XS compiles without errors
- [ ] `make test` passes — XS modules are functionally equivalent to Perl originals

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

| Phase | Description | New Infrastructure | Key Deliverable |
|-------|-------------|-------------------|-----------------|
| 0 | Infrastructure | — | Perl grammar through BNF pipeline |
| 1 | Program skeleton | — | 10-rule subset recognizer |
| 2 | Declarations + literals | ConciseTree semiring | Parses `use`, `my`, literals |
| 3 | Class definitions | — | Parses class/method/field |
| 4 | Expressions | **Precedence + Structural semirings**, ChalkSyntax | Disambiguated expression parsing |
| 5 | Control flow + full grammar | [Arity/TypeInference if needed] | All 31 .pm files recognized |
| 6 | Perl IR | Perl IR node types, SemanticAction | Structured representation of source |
| 7 | Lower to Perl | Perl Target::Perl | Generated Perl matches original |
| 8 | Lower to XS | Perl Target::XS | XS functionally equivalent |
| 9 | Optimizations | Peephole, GCM, Aycock | Same correctness, better performance |

-----

## Decision Log

**Arity/TypeInference semiring: DEFERRED (possibly permanently)**

Bootstrap source consistently uses parenthesized builtin calls (`defined($x)`,
`ref($x)`, `length($x)`). No bare `time + 1` style ambiguity. Exceptions
(`push`, `shift`, `keys`, `die`) use postfix deref or have unambiguous context.
Build it only if Phase 5 full-file recognition reveals actual ambiguity.

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

**File ordering: Stable across Phases 6-8**

One canonical ordering from simplest to most complex, applied consistently.
Tier A files can be batched; Tier D files each deserve individual attention.

**String interpolation: OPAQUE**

`"$var"` and `"text $var more"` matched as opaque string literals by the
`StringLiteral` terminal pattern. No interpolation sub-grammar. XS backend
emits them as Perl double-quoted strings, letting the runtime handle interpolation.
