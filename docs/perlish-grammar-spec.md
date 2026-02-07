# Perl 5.42.0 Bootstrap Subset Grammar Specification

## 1. Purpose

This document specifies a grammar in Chalk::Bootstrap BNF format for recognizing
the Perl 5.42.0 subset used in the Chalk::Bootstrap codebase (~31 `.pm` files
under `lib/Chalk/`).

The grammar is intentionally ambiguous — disambiguation is delegated to semirings
(Precedence, Arity/TypeInference, Structural) rather than encoded in grammar
structure.

**Status**: Future specification. Not yet wired into the Earley parser pipeline.

## 2. Scope

### Included

- `feature class` syntax: `class`, `field`, `method`, `ADJUST`, `:isa()`,
  `:param`, `:reader`
- Modern Perl: signatures, `true`/`false`, postfix deref (`->@*`, `->%*`),
  `isa` operator
- Standard constructs: `use`, `my`/`our`/`local`, `sub`
- Control flow: `if`/`elsif`/`else`, `unless`, `while`/`until`, `for`/`foreach`,
  postfix modifiers
- Expressions: arithmetic, string, comparison, logical, bitwise, ternary,
  assignment, method calls, subscripts
- Literals: strings (single/double quoted), numbers, regex, `qw()`, `qr//`,
  `undef`, `true`, `false`

### Excluded

- Heredocs (eliminate from source; use string concatenation instead)
- Regex/string interpolation internals (treated as opaque terminals)
- `format`, `tie`, `dbmopen`, symbolic refs, `goto`
- Alternate regex delimiters beyond `//` and `{}`
- Special variables beyond `$_`
- Pod documentation

## 3. Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Whitespace | `_` (optional), `WS` (required) | Short, readable, unambiguous |
| Keywords vs identifiers | Accept ambiguity | Arity/TypeInference semiring resolves |
| Operator precedence | Flat (all binary ops at one level) | Precedence semiring resolves |
| Block vs hash `{}` | Accept ambiguity | Structural semiring resolves |
| Regex vs division `/` | Accept ambiguity | Arity semiring resolves |
| Semicolons | Terminator on simple stmts | Compound stmts end with `}`, stand alone |
| Sublanguages | Opaque terminals | Regex bodies, string contents matched as blobs |
| Program structure | Flat `StatementList` | No enforced ordering of declarations |
| Context sensitivity | Allow everything everywhere | Semiring catches invalid placement |
| Expression categories | Separate nonterminals | Readability and semiring hooks |
| Signatures | Own nonterminal | Structurally distinct from expression lists |

## 4. Semiring Requirements

### 4.1 Precedence Semiring

Resolves operator binding strength and associativity for the flat `BinaryExpression`
rule. All binary operators produce `Expression _ BinaryOp _ Expression` — the
Precedence semiring prunes parses that violate precedence/associativity rules.

**Input**: A table mapping each operator pattern to (precedence level, associativity).

**Example**: `$a + $b * $c` produces two parses. The Precedence semiring keeps
only the one where `*` binds tighter than `+`.

### 4.2 Arity/TypeInference Semiring

The workhorse semiring handling multiple disambiguation tasks:

- **Keyword vs identifier**: When `class` appears, is it the keyword or a variable
  name? Consults context and a keyword table.
- **Builtin arity**: `push @arr, $val` — knows `push` takes an array then a list.
  `time + 1` — knows `time` is nullary, so `+` is binary addition.
- **Regex vs division**: After an expression, `/` is division. After an operator
  or at statement start, `/` begins a regex literal.

**Input**: A signature table mapping builtin names to arity and argument types.

### 4.3 Structural Semiring

Handles context-dependent disambiguation:

- **Block vs hash**: `{ ... }` after `if (...)` is a block; `{ ... }` after `=`
  is a hash constructor. Uses position and preceding tokens to decide.
- **Statement context**: `field` is only valid inside a `class` body. The grammar
  allows it everywhere; this semiring prunes invalid placements.

## 5. Grammar Format

The grammar uses Chalk::Bootstrap BNF format (parseable by the BNF meta-grammar
compiler):

- Rules: `Name ::= alternatives ;`
- Alternatives: separated by `|`
- Terminals: `/regex/` (anchored at `\G` during scanning)
- Nonterminals: identifiers (`[A-Za-z_][A-Za-z_0-9]*`)
- Quantifiers: `?` (zero or one), `*` (zero or more), `+` (one or more)
- Quantifiers desugar to helper rules (e.g., `X?` → `X_opt ::= X | epsilon`)

## 6. Grammar Rules

### §1 Whitespace

```bnf
_ ::= /(?:\s|#[^\n]*)*/ ;

WS ::= /(?:\s|#[^\n]*)+/ ;
```

`_` matches zero or more whitespace/comment characters (optional gap).
`WS` requires at least one whitespace or comment character (mandatory gap).
Comments extend from `#` to end of line.

### §2 Program Structure

```bnf
Program ::= _ StatementList? _ ;

StatementList ::= StatementItem
    | StatementList _ StatementItem ;

StatementItem ::= SimpleStatement _ /;/
    | CompoundStatement
    | /;/ ;
```

A program is optional whitespace, an optional statement list, and optional
whitespace. Simple statements carry their own `;` terminator. Compound
statements (ending with `}`) stand alone. Bare `;` is an empty statement,
which naturally allows trailing and repeated semicolons.

### §3 Statement Categories

```bnf
SimpleStatement ::= ExpressionStatement
    | UseDeclaration
    | VariableDeclaration
    | FieldDeclaration ;

CompoundStatement ::= Block
    | IfStatement
    | WhileStatement
    | ForStatement
    | ForeachStatement
    | ClassBlock
    | SubroutineDefinition
    | MethodDefinition
    | AdjustBlock ;
```

### §4 Expression Statements

```bnf
ExpressionStatement ::= Expression
    | Expression WS PostfixModifier ;

PostfixModifier ::= /(?:if|unless|while|until|for|foreach)\b/ WS Expression ;
```

Postfix modifiers attach to any expression: `return unless $done`,
`push @arr, $val for $list->@*`.

### §5 Conditionals

```bnf
IfStatement ::= /(?:if|unless)\b/ _ ParenExpr _ Block ElsifChain? ;

ElsifChain ::= _ /elsif\b/ _ ParenExpr _ Block ElsifChain?
    | _ /else\b/ _ Block ;
```

`if` and `unless` share syntax via alternation in the keyword pattern.
The elsif chain is optional and recursive, terminated by an optional `else`.

### §6 Loops

```bnf
WhileStatement ::= /(?:while|until)\b/ _ ParenExpr _ Block ;

ForStatement ::= /for\b/ _ /\(/ _ Expression? _ /;/ _ Expression? _ /;/
    _ Expression? _ /\)/ _ Block ;

ForeachStatement ::= /(?:for|foreach)\b/ WS IteratorVariable _ ParenExpr _ Block
    | /(?:for|foreach)\b/ _ ParenExpr _ Block ;

IteratorVariable ::= /my\b/ WS ScalarVariable
    | ScalarVariable ;
```

`ForStatement` is C-style `for (init; cond; step)`. `ForeachStatement` is
list iteration. Both `for` and `foreach` keywords are accepted for either form.

### §7 Use Declarations

```bnf
UseDeclaration ::= /use\b/ WS ModuleName
    | /use\b/ WS ModuleName WS ImportList ;

ModuleName ::= QualifiedIdentifier
    | Version
    | QualifiedIdentifier WS Version ;

ImportList ::= ExpressionList ;
```

Handles: `use 5.42.0`, `use utf8`, `use experimental 'class'`.

### §8 Variable and Field Declarations

```bnf
VariableDeclaration ::= /(?:my|our|state|local)\b/ WS Variable
    | /(?:my|our|state|local)\b/ WS Variable _ /=/ _ Expression
    | /(?:my|our|state|local)\b/ WS /\(/ _ VariableList _ /\)/
    | /(?:my|our|state|local)\b/ WS /\(/ _ VariableList _ /\)/ _ /=/ _ Expression ;

VariableList ::= Variable
    | VariableList _ /,/ _ Variable ;

FieldDeclaration ::= /field\b/ WS Variable AttributeList? DefaultValue? ;

DefaultValue ::= _ /=/ _ Expression ;
```

Handles: `my $x`, `my $x = 1`, `our @EXPORT_OK = (...)`,
`my ($x, $y) = @list`, `field $name :param :reader = undef`.

### §9 Definitions

```bnf
ClassBlock ::= /class\b/ WS QualifiedIdentifier AttributeList? _ Block ;

SubroutineDefinition ::= /sub\b/ WS Identifier _ Signature? _ Block
    | /(?:my|our|state)\b/ WS /sub\b/ WS Identifier _ Signature? _ Block ;

MethodDefinition ::= /method\b/ WS Identifier AttributeList? _ Signature? _ Block ;

AdjustBlock ::= /ADJUST\b/ _ Block ;
```

The second `SubroutineDefinition` alternative handles lexically scoped subs:
`my sub _helper { ... }`.

### §10 Attributes

```bnf
AttributeList ::= WS Attribute
    | AttributeList WS Attribute ;

Attribute ::= /:/ _ Identifier
    | /:/ _ Identifier _ /\(/ _ QualifiedIdentifier _ /\)/ ;
```

`AttributeList` includes leading whitespace so `AttributeList?` at call sites
handles spacing naturally. Covers: `:param`, `:reader`, `:isa(Parent::Class)`.

### §11 Signatures

```bnf
Signature ::= /\(/ _ /\)/
    | /\(/ _ SignatureParams _ /\)/ ;

SignatureParams ::= SignatureParam
    | SignatureParams _ /,/ _ SignatureParam
    | SignatureParams _ /,/ ;

SignatureParam ::= ScalarSignatureParam
    | SlurpySignatureParam ;

ScalarSignatureParam ::= ScalarVariable
    | ScalarVariable _ /=/ _ Expression ;

SlurpySignatureParam ::= ArrayVariable
    | HashVariable ;
```

Trailing comma is allowed via `SignatureParams _ /,/`. Covers:
`($x)`, `($x, $y)`, `($x = undef)`, `($operation, %params)`.

### §12 Expressions

```bnf
Expression ::= Atom
    | UnaryExpression
    | BinaryExpression
    | PostfixExpression
    | TernaryExpression
    | AssignmentExpression ;

ExpressionList ::= Expression
    | ExpressionList _ /,/ _ Expression
    | ExpressionList _ /=>/ _ Expression
    | ExpressionList _ /,/ ;
```

`ExpressionList` includes fat comma `=>` for hash-style pairs and allows
trailing commas. All operators in `Expression` are at the same structural
level — the Precedence semiring resolves binding.

### §13 Atoms

```bnf
Atom ::= Variable
    | Literal
    | ParenExpr
    | ArrayConstructor
    | HashConstructor
    | QwLiteral
    | AnonymousSub
    | Identifier ;

ParenExpr ::= /\(/ _ Expression _ /\)/
    | /\(/ _ ExpressionList _ /\)/
    | /\(/ _ /\)/ ;

ArrayConstructor ::= /\[/ _ ExpressionList? _ /\]/ ;

HashConstructor ::= /\{/ _ ExpressionList? _ /\}/ ;

AnonymousSub ::= /sub\b/ _ Signature? _ Block ;

QwLiteral ::= /qw\s*\([^)]*\)/ ;
```

`HashConstructor` and `Block` both match `{ ... }` — this is the
block-vs-hash ambiguity resolved by the Structural semiring.

### §14 Unary Expressions

```bnf
UnaryExpression ::= /!/ _ Expression
    | /-/ _ Expression
    | /\+/ _ Expression
    | /~/ _ Expression
    | /\\/ _ Expression
    | /not\b/ WS Expression ;
```

`\` creates references: `\@rules`. The `not` keyword requires mandatory
whitespace before its operand.

### §15 Binary Expressions

```bnf
BinaryExpression ::= Expression _ BinaryOp _ Expression ;

BinaryOp ::= /\*\*/
    | /[*\/%]/
    | /x\b/
    | /[+-]/
    | /\.(?!\.)/
    | /<</
    | />>/
    | /<=>/
    | /[<>]=?/
    | /[!=]=/
    | /(?:eq|ne|lt|gt|le|ge|cmp)\b/
    | /=~/
    | /!~/
    | /&&/
    | /\|\|/
    | /\/\//
    | /(?:and|or|xor)\b/
    | /&(?!&)/
    | /\|(?!\|)/
    | /\^/
    | /\.\.\.?/
    | /isa\b/ ;
```

All binary operators at one level. The Precedence semiring resolves binding
strength. Negative lookaheads prevent `&&` matching as two `&` operators, etc.
The `.` (concat) uses `/\.(?!\.)/` to avoid matching `..` (range).

### §16 Postfix Expressions

```bnf
PostfixExpression ::= MethodCall
    | Subscript
    | PostfixDeref
    | CallExpression
    | PostfixIncDec ;

MethodCall ::= Expression _ /->/ _ Identifier _ /\(/ _ ExpressionList? _ /\)/
    | Expression _ /->/ _ Identifier ;

Subscript ::= Expression _ /->/ _ /\[/ _ Expression _ /\]/
    | Expression _ /->/ _ /\{/ _ Expression _ /\}/
    | Expression _ /->/ _ /\(/ _ ExpressionList? _ /\)/
    | Expression _ /\[/ _ Expression _ /\]/
    | Expression _ /\{/ _ Expression _ /\}/ ;

PostfixDeref ::= Expression _ /->/ _ /@\*/
    | Expression _ /->/ _ /%\*/
    | Expression _ /->/ _ /\$\*/
    | Expression _ /->/ _ /\$#\*/ ;

CallExpression ::= Identifier _ /\(/ _ ExpressionList? _ /\)/
    | QualifiedIdentifier _ /\(/ _ ExpressionList? _ /\)/
    | Identifier WS ExpressionList
    | Identifier WS Block WS ExpressionList
    | Identifier WS Block ;

PostfixIncDec ::= Expression _ /\+\+/
    | Expression _ /--/ ;
```

`MethodCall` handles `$obj->method()` and `$obj->method` (no-arg).
`Subscript` handles both arrow (`$ref->[$i]`) and direct (`$arr[$i]`) forms.
`PostfixDeref` handles modern Perl postfix dereference: `$ref->@*`, `$ref->%*`.
`CallExpression` handles parenthesized calls, bare calls (`push @arr, $val`),
and block-first calls (`map { ... } @list`, `grep { ... } @list`).

### §17 Ternary and Assignment

```bnf
TernaryExpression ::= Expression _ /\?/ _ Expression _ /:/ _ Expression ;

AssignmentExpression ::= Expression _ AssignOp _ Expression ;

AssignOp ::= /=(?![=>])/
    | /\*\*=/
    | /[*\/%+\-&|^.]=/
    | /&&=/
    | /\|\|=/
    | /\/\/=/
    | /<<=/
    | />>=/  ;
```

Plain `=` uses negative lookahead `/=(?![=>])/` to avoid matching `==` or `=>`.

### §18 Variables

```bnf
Variable ::= ScalarVariable
    | ArrayVariable
    | HashVariable ;

ScalarVariable ::= /\$[a-zA-Z_]\w*/ ;

ArrayVariable ::= /@[a-zA-Z_]\w*/ ;

HashVariable ::= /%[a-zA-Z_]\w*/ ;
```

Variables are single-token terminals: sigil + identifier name.
Covers `$self`, `$_`, `@rules`, `%hash`, `@EXPORT_OK`.

### §19 Literals

```bnf
Literal ::= NumericLiteral
    | StringLiteral
    | RegexLiteral
    | /undef\b/
    | /true\b/
    | /false\b/ ;

NumericLiteral ::= /0[xX][0-9a-fA-F](?:_?[0-9a-fA-F])*/
    | /0[bB][01](?:_?[01])*/
    | /0[oO]?[0-7](?:_?[0-7])*/
    | /[0-9](?:_?[0-9])*(?:\.[0-9](?:_?[0-9])*)?(?:[eE][+-]?[0-9]+)?/ ;

StringLiteral ::= /'(?:[^'\\]|\\.)*'/
    | /"(?:[^"\\]|\\.)*"/ ;

RegexLiteral ::= /\/(?:[^\/\\]|\\.)*\/[msixpodualngcer]*/
    | /m\s*\/(?:[^\/\\]|\\.)*\/[msixpodualngcer]*/
    | /qr\s*\/(?:[^\/\\]|\\.)*\/[msixpodualngcer]*/
    | /s\s*\/(?:[^\/\\]|\\.)*\/(?:[^\/\\]|\\.)*\/[msixpodualngcer]*/
    | /s\s*\{(?:[^}\\]|\\.)*\}\s*\{(?:[^}\\]|\\.)*\}[msixpodualngcer]*/ ;
```

`NumericLiteral` covers hex (`0xFF`), binary (`0b1010`), octal (`0o77`),
decimal integers, and floats (`3.14`, `1e10`). Underscores allowed as
digit separators.

`StringLiteral` treats contents as opaque — no interpolation parsing.

`RegexLiteral` covers bare regex (`/pattern/flags`), explicit match
(`m/.../flags`), quoted regex (`qr/.../flags`), and substitution
(`s/pat/repl/flags` with both `//` and `{}` delimiters).

### §20 Identifiers and Helpers

```bnf
Identifier ::= /[a-zA-Z_]\w*/ ;

QualifiedIdentifier ::= /[a-zA-Z_]\w*(?:::[a-zA-Z_]\w*)*/ ;

Block ::= /\{/ _ StatementList? _ /\}/ ;

Version ::= /v?[0-9]+(?:\.[0-9]+){2,}/ ;
```

`QualifiedIdentifier` matches `Foo::Bar::Baz` (module/class names).
`Block` is a braced statement list (also matches as `HashConstructor` —
ambiguity resolved by Structural semiring).
`Version` matches Perl version literals like `5.42.0` and `v5.42.0`.

## 7. Terminal Pattern Catalog

Summary of all terminal regex patterns used:

| Category | Pattern | Matches |
|---|---|---|
| Whitespace | `/(?:\s\|#[^\n]*)*/` | Optional whitespace + comments |
| Whitespace | `/(?:\s\|#[^\n]*)+/` | Required whitespace + comments |
| Semicolon | `/;/` | Statement terminator |
| Keywords | `/(?:if\|unless)\b/` | Conditional keywords |
| Keywords | `/elsif\b/` | Elsif keyword |
| Keywords | `/else\b/` | Else keyword |
| Keywords | `/(?:while\|until)\b/` | Loop keywords |
| Keywords | `/for\b/`, `/(?:for\|foreach)\b/` | For/foreach keywords |
| Keywords | `/use\b/` | Import pragma |
| Keywords | `/(?:my\|our\|state\|local)\b/` | Declarators |
| Keywords | `/class\b/`, `/field\b/`, `/method\b/` | Class features |
| Keywords | `/sub\b/`, `/ADJUST\b/` | Other declarations |
| Keywords | `/(?:if\|unless\|while\|until\|for\|foreach)\b/` | Postfix modifiers |
| Keywords | `/not\b/`, `/(?:and\|or\|xor)\b/` | Word operators |
| Keywords | `/(?:eq\|ne\|lt\|gt\|le\|ge\|cmp)\b/` | String comparison |
| Keywords | `/isa\b/`, `/x\b/` | Misc operators |
| Literals | `/undef\b/`, `/true\b/`, `/false\b/` | Special literals |
| Scalar | `/\$[a-zA-Z_]\w*/` | Scalar variable |
| Array | `/@[a-zA-Z_]\w*/` | Array variable |
| Hash | `/%[a-zA-Z_]\w*/` | Hash variable |
| Identifier | `/[a-zA-Z_]\w*/` | Simple name |
| Qualified | `/[a-zA-Z_]\w*(?:::[a-zA-Z_]\w*)*/` | Package::Name |
| Version | `/v?[0-9]+(?:\.[0-9]+){2,}/` | Version literal |
| Number | `/0[xX][0-9a-fA-F](?:_?[0-9a-fA-F])*/` | Hex integer |
| Number | `/0[bB][01](?:_?[01])*/` | Binary integer |
| Number | `/0[oO]?[0-7](?:_?[0-7])*/` | Octal integer |
| Number | `/[0-9](?:_?[0-9])*(?:\.[0-9]...)?(?:[eE]...)?/` | Decimal/float |
| String | `/'(?:[^'\\]\|\\.)*'/` | Single-quoted |
| String | `/"(?:[^"\\]\|\\.)*"/` | Double-quoted |
| Regex | `/\/(?:[^\/\\]\|\\.)*\/[flags]*/` | Regex literal |
| Regex | `/qr\s*\/(?:[^\/\\]\|\\.)*\/[flags]*/` | Quoted regex |
| Regex | `/s\s*\/...\/.../[flags]*/` | Substitution |
| QW | `/qw\s*\([^)]*\)/` | Quoted words |
| Operators | `/\*\*/`, `/[*\/%]/`, `/[+-]/`, etc. | Binary ops |
| Assignment | `/=(?![=>])/`, `/\*\*=/`, etc. | Assignment ops |
| Delimiters | `/\(/`, `/\)/`, `/\[/`, `/\]/`, `/\{/`, `/\}/` | Brackets |
| Arrow | `/\->/` | Method/deref arrow |
| Deref | `/@\*/`, `/%\*/`, `/\$\*/`, `/\$#\*/` | Postfix deref |
| Misc | `/:/`, `/\?/`, `/\+\+/`, `/--/`, `/!/`, `/\\/` | Misc operators |

## 8. Testing Plan

### 8.1 Progressive Layer Testing

Following the established Chalk pattern of testing each layer independently:

**Layer 1 — Individual Rules**: Test each grammar rule in isolation with
minimal inputs. Verify each nonterminal accepts expected strings and rejects
invalid ones.

```
# Example: VariableDeclaration
"my $x"           → accept
"my $x = 1"       → accept
"my ($x, $y)"     → accept
"$x = 1"          → reject (no declarator)
```

**Layer 2 — Statement Recognition**: Test complete statements (simple with `;`,
compound with blocks).

```
# Example: SimpleStatement
"use 5.42.0;"           → accept
"my $x = 1;"            → accept
"field $name :param;"   → accept

# Example: CompoundStatement
"if ($x) { }"                     → accept
"class Foo :isa(Bar) { }"         → accept
"method name($arg) { return; }"   → accept
```

**Layer 3 — Expression Parsing**: Test the flat expression grammar produces
parses (multiple parses expected due to intentional ambiguity).

```
# These should parse (possibly ambiguously):
"$a + $b * $c"       → accept (2+ parses, Precedence semiring resolves)
"$obj->method()"     → accept
"$ref->@*"           → accept
"$x ? $y : $z"       → accept
```

**Layer 4 — Full File Recognition**: Parse each bootstrap `.pm` file.

```
# Each file should be accepted:
lib/Chalk/Grammar/Symbol.pm       → accept
lib/Chalk/Grammar/Rule.pm         → accept
lib/Chalk/Bootstrap/Earley.pm     → accept
lib/Chalk/Bootstrap/Context.pm    → accept
# ... all 31 .pm files
```

### 8.2 Source Preparation

Before Layer 4 testing, eliminate heredocs from bootstrap source files.
Replace heredoc usage in `Target::Perl.pm` and `Target::XS.pm` with
string concatenation or `join()` equivalents.

### 8.3 Ambiguity Validation

For key ambiguous constructs, verify the parser produces multiple parses
and that the correct parse is among them:

- `$a + $b * $c` — both `(a+b)*c` and `a+(b*c)` parses exist
- `{ $x => $y }` — both Block and HashConstructor parses exist
- `time + 1` — both `time(+1)` and `time + 1` parses exist
- `/pattern/` after `=~` — regex parse exists

### 8.4 Regression Tests

After each grammar change, re-run all Layer 4 tests to ensure no regressions.
Track the set of accepted files and ensure it never shrinks.

## 9. Known Limitations

1. **No heredoc support**: Heredocs must be eliminated from source before parsing.
   This is a preprocessing step, not a grammar limitation.

2. **Opaque sublanguages**: Regex bodies, string contents, and `qw()` word lists
   are matched as blobs. Internal syntax errors won't be caught by this grammar.

3. **No format declarations**: The `format` keyword's special body syntax is
   not supported. Not used in bootstrap code.

4. **Limited special variables**: Only `$name`, `@name`, `%name` forms. No `$!`,
   `$$`, `$?`, `@_`, `%ENV`, etc. (Can be extended with broader terminal patterns.)

5. **Ambiguity explosion**: The flat expression grammar with all operators at one
   level produces many ambiguous parses for complex expressions. The Earley parser
   handles this, but performance may degrade for deeply nested expressions.
   The semirings must be efficient at pruning.

6. **No string interpolation**: `"Hello $name"` is matched as an opaque string
   literal. Variable references inside strings are not recognized.

7. **Regex delimiter limitation**: Only `//` and `{}` delimiters for substitution.
   Other delimiter pairs (`()`, `[]`, `||`, etc.) not supported.

## 10. Future Work

1. **Semiring implementation**: Implement the three required semirings
   (Precedence, Arity/TypeInference, Structural) and wire them into the
   Earley parser as a Composite semiring.

2. **Wire into pipeline**: Make this grammar parseable by the BNF meta-grammar
   compiler, generating a recognizer that can be tested against bootstrap source.

3. **Heredoc elimination**: Refactor `Target::Perl.pm` and `Target::XS.pm` to
   replace heredocs with string concatenation.

4. **Performance testing**: Measure parse time for full `.pm` files with the
   flat ambiguous grammar. If too slow, consider selectively encoding some
   precedence levels in grammar structure (hybrid approach).

5. **Extend to full Chalk**: Once the bootstrap subset works, extend to cover
   the broader Chalk codebase syntax.

6. **CST construction**: Add a CST semiring to preserve comments and whitespace
   for formatting-preserving transformations.

## 11. Rule Summary

| Section | Rules | Count |
|---|---|---|
| §1 Whitespace | `_`, `WS` | 2 |
| §2 Program Structure | `Program`, `StatementList`, `StatementItem` | 3 |
| §3 Statement Categories | `SimpleStatement`, `CompoundStatement` | 2 |
| §4 Expression Statements | `ExpressionStatement`, `PostfixModifier` | 2 |
| §5 Conditionals | `IfStatement`, `ElsifChain` | 2 |
| §6 Loops | `WhileStatement`, `ForStatement`, `ForeachStatement`, `IteratorVariable` | 4 |
| §7 Use | `UseDeclaration`, `ModuleName`, `ImportList` | 3 |
| §8 Variables/Fields | `VariableDeclaration`, `VariableList`, `FieldDeclaration`, `DefaultValue` | 4 |
| §9 Definitions | `ClassBlock`, `SubroutineDefinition`, `MethodDefinition`, `AdjustBlock` | 4 |
| §10 Attributes | `AttributeList`, `Attribute` | 2 |
| §11 Signatures | `Signature`, `SignatureParams`, `SignatureParam`, `ScalarSignatureParam`, `SlurpySignatureParam` | 5 |
| §12 Expressions | `Expression`, `ExpressionList` | 2 |
| §13 Atoms | `Atom`, `ParenExpr`, `ArrayConstructor`, `HashConstructor`, `AnonymousSub`, `QwLiteral` | 6 |
| §14 Unary | `UnaryExpression` | 1 |
| §15 Binary | `BinaryExpression`, `BinaryOp` | 2 |
| §16 Postfix | `PostfixExpression`, `MethodCall`, `Subscript`, `PostfixDeref`, `CallExpression`, `PostfixIncDec` | 6 |
| §17 Ternary/Assignment | `TernaryExpression`, `AssignmentExpression`, `AssignOp` | 3 |
| §18 Variables | `Variable`, `ScalarVariable`, `ArrayVariable`, `HashVariable` | 4 |
| §19 Literals | `Literal`, `NumericLiteral`, `StringLiteral`, `RegexLiteral` | 4 |
| §20 Helpers | `Identifier`, `QualifiedIdentifier`, `Block`, `Version` | 4 |
| **Total** | | **65** |

With quantifier desugaring (`?`, `*`, `+` → helper rules), the effective
rule count at parse time will be approximately 74-79 rules.
