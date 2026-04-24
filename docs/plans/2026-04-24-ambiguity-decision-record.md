# Ambiguity Decision Record — Grammar-Encode vs Semiring-Resolve vs Restrict

**Status:** Analysis / audit. Read-only report, no code changes proposed.
**Scope:** Nine ambiguity points enumerated in
`docs/architecture/ambiguity-classes.md`.
**Date:** 2026-04-24.

## Overview

Chalk's architecture treats grammar ambiguity as a deliberate design
decision. Nine ambiguity points are catalogued in
`docs/architecture/ambiguity-classes.md` — seven resolved by filtering
semirings (Boolean → Precedence → TypeInference → Structural →
SemanticAction), two excluded-by-restriction. Only Class 1 (binary
operator precedence) has a recorded rationale for why the semiring
layer was chosen over grammar encoding: encoding Perl's ~24 precedence
levels in BNF causes rule explosion. The other eight classifications
are load-bearing assertions with no documented rationale.

This report audits those assertions. For each of the nine points it
answers two questions:

1. **Where does Perl's own implementation handle this?** — file and
   line in `toke.c` (the tokenizer / stateful lexer), `perly.y` (the
   bison grammar), or elsewhere.
2. **What's the grammar-encoding cost in Chalk?** — a rough estimate
   of the rule-count delta that grammar-encoding would require, plus
   interaction effects with the existing grammar.

From those two answers the report recommends one of three dispositions
for each point: grammar-encode, semiring-resolve, or restrict-out.
Precedence (Class 1) is the paradigm example of "semiring was right":
the grammar-cost is multiplicative (operators × precedence levels),
the cost dominates, the semiring is cheaper. Other classes with that
shape belong in the semiring layer; others may not.

## Methodology

### Files read

- `docs/architecture/ambiguity-classes.md` — the document under audit.
- `docs/chalk-bootstrap.bnf` — the 63-rule Perl grammar, specifically
  `Expression`, `UnaryExpression`, `BinaryExpression`, `BinaryOp`,
  `CallExpression`, `Atom`, `Block`, `HashConstructor`, `RegexLiteral`,
  `Literal`, `QualifiedIdentifier`.
- `docs/chalk-grammar-spec.md` §3 (Design Decisions), §4 (Semiring
  Requirements), §9 (Known Limitations).
- `lib/Chalk/Bootstrap/Semiring/Structural.pm` — `_complete_structural`
  tag-flow, `add()` preference rules.
- `lib/Chalk/Bootstrap/Semiring/Precedence.pm` — `_scan_multiply`,
  `_complete_prec`, `_prec_multiply`.
- `lib/Chalk/Bootstrap/Semiring/TypeInference.pm` — actions dispatch,
  scan-time cache.
- `docs/plans/2026-04-24-option-b-grammar-refactor-postmortem.md` — a
  recent attempt to grammar-encode a small pseudo-ambiguity (single-
  vs multi-element `ExpressionList`) that was rolled back. Useful
  empirical evidence for the difficulty of grammar-encoding changes
  that reshape `CallExpression` alt indices.
- `perl5/toke.c` (14068 lines) — Perl's stateful tokenizer.
- `perl5/perly.y` (1620 lines) — Perl's bison grammar.

### What I searched for, in what

- `PL_expect` machine states (`XTERM`, `XOPERATOR`, `XBLOCK`, `XSTATE`,
  `XREF`, `XTERMBLOCK`) — the core of Perl's stateful disambiguation.
- Per-character dispatch: `yyl_slash`, `yyl_hyphen`, `yyl_leftcurly`,
  `yyl_just_a_word`, `yyl_word_or_keyword`, `S_intuit_method`.
- Per-keyword classification: the `UNI(OP_*)` vs `LOP(OP_*)` vs
  `FUN0(...)` calls in the big switch starting at `toke.c:7946`.
- `perly.y` precedence declarations (`%left`, `%right`, `%nonassoc`).
- `perly.y` `listop` rule (the production that consumes `LSTOP` /
  `BLKLSTOP` / `METHCALL0`).

### Grammar-cost estimation

For each class I counted:

- **New terminals / keyword patterns** — typically one if a new word
  class is introduced.
- **New nonterminals** — e.g. splitting `Expression` into tiers.
- **New alternatives** — typically multiplicative when the ambiguity
  class is orthogonal to something else already in the grammar.
- **Touching existing alternatives** — rule alts referenced by
  `Structural.pm` and `TypeInferenceActions.pm` are keyed by
  `(rule_name, alt_idx)`. Renumbering alts in a rule is a real
  cost: the postmortem document cited four concrete semiring sites
  that break when `ExpressionList` alts are renumbered.

Cost estimates are rough. Where cost is clearly bounded (a small
constant), I say so. Where cost clearly explodes (multiplicative in
an orthogonal dimension), I say that. Borderline cases are flagged.

## Per-ambiguity analysis

### Class 1: Precedence (binary operator binding)

**Perl example:**

```perl
$a + $b * $c
$x || $y && $z
$a ? $b : $c ? $d : $e
```

**Where Perl handles it:** `perly.y` — the bison precedence table
itself. See declarations `perly.y:123-155`:

```
%nonassoc <ival> PREC_LOW
%nonassoc LOOPEX
%nonassoc <pval> PLUGIN_LOW_OP
%left <ival> OROP ...
%left <ival> ANDOP ...
%right <ival> NOTOP
%nonassoc LSTOP LSTOPSUB BLKLSTOP
%left PERLY_COMMA
%right <ival> ASSIGNOP ...
%right <ival> PERLY_QUESTION_MARK PERLY_COLON
%nonassoc DOTDOT
%left <ival> OROR DORDOR ...
...
%left <ival> SHIFTOP
%left ADDOP <pval> PLUGIN_ADD_OP
%left MULOP <pval> PLUGIN_MUL_OP
%left <ival> MATCHOP
%right <ival> PERLY_EXCLAMATION_MARK PERLY_TILDE UMINUS REFGEN
%right POWOP <pval> PLUGIN_POW_OP
%nonassoc <ival> PREINC PREDEC POSTINC POSTDEC POSTJOIN
%nonassoc <pval> PLUGIN_HIGH_OP
%left <ival> ARROW
%nonassoc <ival> PERLY_PAREN_CLOSE
%left <ival> PERLY_PAREN_OPEN
%left PERLY_BRACKET_OPEN PERLY_BRACE_OPEN
```

Bison resolves shift/reduce conflicts using the precedence table at
parser-generator time. The generated LALR(1) tables encode the
disambiguation; at parse time there is no separate decision layer.

**Chalk grammar-encoding cost:** Very high. Encoding ~24 precedence
levels would require splitting `BinaryExpression` into ~24 tiered
nonterminals with `_left`/`_right` variants for associativity:
`MulExpr ::= UnaryExpr | MulExpr _ /[*\/%]/ _ UnaryExpr` × 24. Each
operator class becomes its own rule, plus the ternary and assignment
tiers. Rough delta: **1 rule (`BinaryExpression`) → ~24 rules** plus
a cascade of "which tier is at each level" bookkeeping. Additionally
this hardcodes the operator set — adding a new operator (e.g.
user-defined infix) requires grammar surgery.

**Chalk's current choice:** Precedence semiring. `BinaryExpression`
is a single flat rule; the Precedence semiring consults
`PrecedenceTable::lookup($op_text)` at scan time and rejects
derivations whose operator tree violates the table's ordering
(`Semiring/Precedence.pm:136-150`).

**Recommendation:** **Semiring** (unchanged).

**Reasoning:** This is the paradigm case for semiring resolution.
Grammar-encoding causes quadratic blowup (operators × levels), bison
avoids this via external precedence declarations that are *not* part
of the grammar proper, and Chalk's semiring recreates exactly that
structure (a table consulted outside the grammar). Chalk's choice
is correct.

---

### Class 2: Keyword vs identifier

**Perl example:**

```perl
class Foo { }          # 'class' is a keyword
class => 'Foo'         # 'class' is an identifier (hash key)
return $x              # 'return' is a keyword
if ($x) { ... }        # 'if' is a keyword
my $return = 1         # bareword 'return' on the RHS would still be keyword in Perl;
                       # Chalk's subset excludes runtime symbol access anyway.
```

**Where Perl handles it:** `toke.c` — bareword-reading routines are
dispatched through `S_keyword` (implemented in generated `keywords.c`
via `keywords.h`). The relevant decision path is:

1. `toke.c:7946` — `yyl_word_or_keyword` dispatches on a keyword ID
   returned from `keyword()`.
2. `toke.c:8048-8055` — per-keyword handling; e.g. `KEY_class`:

   ```c
   case KEY_class:
       ck_warner_d(packWARN(WARN_EXPERIMENTAL__CLASS), "class is experimental");
       s = force_word(s,BAREWORD,FALSE,TRUE);
       s = skipspace(s);
       s = force_strict_version(s);
       PL_expect = XATTRBLOCK;
       TOKEN(KW_CLASS);
   ```

3. `toke.c:7849-7864` — the fat-arrow escape: if the bareword is
   followed by `=>`, it is quoted automatically regardless of keyword
   status. (Returns `BAREWORD`, not the keyword token.)
4. `toke.c:9060-9068` — label detection (`foo:`) upgrades the bareword
   to `LABEL`.

The mechanism is **stateful and lookahead-driven**: the tokenizer
reads the word, checks the keyword table, checks the following
character (`=>`, `:`), and emits different token types
(`KW_CLASS`, `BAREWORD`, `LABEL`) depending on context.

**Chalk grammar-encoding cost:** Moderate-to-high. Two viable
encodings:

1. **Split `QualifiedIdentifier`** into `KeywordOrIdentifier` (matches
   everything incl. keywords) and `NonKeywordIdentifier` (matches only
   non-keywords). The non-keyword regex is either a negative-lookahead
   (`/(?!(if|class|sub|...)\b)[a-zA-Z_]\w*(?:::[a-zA-Z_]\w*)*/`) or a
   reorder-the-alts-so-keyword-rule-wins-first trick. Cost: **~1-2
   extra rules**, but the regex is long and every new keyword added
   requires updating the negative lookahead. Crucially, this *still*
   doesn't help with the fat-arrow case — `class => 'Foo'` needs
   `class` to be an identifier only when followed by `=>`, which
   BNF cannot express without infinite lookahead or a whole new
   context-sensitive form.

2. **Grammar-encode the fat-arrow case specifically:**
   `ExpressionList ::= KeywordOrIdentifier _ /=>/ _ Expression | ...`.
   Requires duplication of every rule that can appear as an LHS of
   `=>`. Cost: unbounded (it's every expression-list site).

Neither encoding eliminates the need for some context-sensitive
mechanism. The fat-arrow case is fundamentally a lookahead — it's
"is this bareword followed by `=>` at this position?" — and Chalk's
current mechanism of "let the rule `QualifiedIdentifier` fire and
let `ClassBlock` not be predicted in this context" is exactly the
Earley-native equivalent of that lookahead.

**Chalk's current choice:** TypeInference semiring. `KeywordTable::is_keyword()`
identifies keywords; `TypeInference::should_scan()` rejects a
`QualifiedIdentifier` scan for keywords when a consuming rule (e.g.
`ClassBlock`) is predicted at that position. In `ExpressionList`
context, `ClassBlock` is not predicted, so `class` scans as a
`QualifiedIdentifier`.

**Recommendation:** **Semiring** (unchanged).

**Reasoning:** Perl does this statefully with keyword tables and
lookahead; BNF cannot. A negative-lookahead regex approach
partially works but still fails on fat-arrow (where the keyword
*must* be admitted as an identifier). The semiring's "is the
consuming rule currently predicted?" check is the Earley-native
form of "what does the parser expect at this position" — exactly
Perl's `PL_expect`-driven logic, implemented in terms of the Earley
chart instead of a state machine. Chalk's choice is correct.

---

### Class 3: Block vs hash constructor

**Perl example:**

```perl
if ($x) { $y }                  # Block
my $h = { a => 1 }              # HashConstructor
return { a => 1 }               # HashConstructor
map { $_->name } @arr           # Block (class 7)
```

**Where Perl handles it:** `toke.c:6320-6520` — `yyl_leftcurly` uses
the `PL_expect` state machine. Key lines:

- `toke.c:6327-6332` — `case XTERM`/`XTERMORDORDOR`: brace is a
  hash; emit `HASHBRACK` token.
- `toke.c:6364-6369` — `case XATTRBLOCK`/`XBLOCK`: brace is a block.
- `toke.c:6375+` (`default:`) — fallback heuristics when state is
  ambiguous: scan ahead looking for `'string' ,`, `q{...},`,
  `word =>`, etc. If a bareword or quoted string is immediately
  followed by `,` or `=>`, it's an anon hash (`HASHBRACK`). If a
  nested `{` appears, treat the outer as a block.

```c
/* if comma follows first term, call it an anon hash */
if (t < PL_bufend && ((*t == ',' && (*s == 'q' || !isLOWER(*s)))
                   || (*t == '=' && t[1] == '>')))
    OPERATOR(HASHBRACK);
```

The parser then has separate grammar productions for `HASHBRACK ...`
(anon hash) vs `{` (block), gated by the token emitted.

**Chalk grammar-encoding cost:** Impossible without essentially
re-implementing the lookahead heuristics. The BNF rules are:

```
HashConstructor ::= /\{/ _ ExpressionList? _ /\}/ ;
Block           ::= /\{/ _ StatementList? _ /\}/
                  | /\{/ _ StatementList? _ SimpleStatement _ /\}/ ;
```

Both match `{ ... }` at the same position. Grammar-encoding the
distinction requires site-specific splitting. You'd have to replace
every position where `Block` appears (e.g. `IfStatement`,
`WhileStatement`, `SubroutineDefinition`, `MethodDefinition`, etc.
— ~12 rule alternatives) with a `BlockOnly` nonterminal, and every
position where `HashConstructor` appears (e.g. `Atom`) with
`HashConstructorOnly`. For the **orphan** cases — map/grep/sort
where the block-vs-hash choice really is ambiguous at that exact
position — the grammar still needs to encode both and would simply
push the decision downstream again.

Rough delta: **~1 new rule (`BlockOnly` = copy of current `Block`),
no real change to `HashConstructor`, but ~12 call-site rewrites**.
The catch: `map { ... } @arr` remains ambiguous because the grammar
admits `CallExpression ::= QualifiedIdentifier WS Block WS ExpressionList`
*and* `CallExpression ::= QualifiedIdentifier WS ExpressionList`
where the `{...}` inside `ExpressionList` could be a `HashConstructor`.
That's Class 7 and the grammar still doesn't resolve it there.

**Chalk's current choice:** Structural semiring. Block and
HashConstructor both succeed recognition. Structural tags completions
with `STRUCT_IS_BLOCK` (bit 0) or `STRUCT_IS_HASH` (bit 1), and
`add()` picks the tag-set preferred by enclosing rules' alt-index
preferences (`Structural.pm:107-114`, `150-152`, `242-256`).

**Recommendation:** **Semiring** (unchanged).

**Reasoning:** Perl does this with `PL_expect` + lookahead (stateful
tokenization). Chalk's Earley parser doesn't have access to a
pre-lex `PL_expect` — the equivalent signal ("what does the enclosing
rule want here?") arrives *after* the brace is consumed, in the form
of the enclosing rule context at completion time. That's exactly what
the Structural semiring uses: the brace-group is tagged with both
possibilities during completion, and the containing rule picks at
`add()`. Grammar-encoding would require either (a) pre-lex
disambiguation (not available) or (b) duplicating ~12 call sites
without actually resolving the hard cases (map/grep/sort). Chalk's
choice is correct.

---

### Class 4: Slash as division vs regex delimiter

**Perl example:**

```perl
my $re = /foo/;        # regex
my $x = $a / $b;       # division
$x =~ /foo/            # regex (binding context)
print /foo/            # regex (list op expects term)
```

**Where Perl handles it:** `toke.c:6733-6763` — `yyl_slash` is a
direct dispatch on `PL_expect`:

```c
yyl_slash(pTHX_ char *s)
{
    if ((PL_expect == XOPERATOR || PL_expect == XTERMORDORDOR) && s[1] == '/') {
        /* '//' is defined-or */
        s += 2;
        AOPERATOR(DORDOR);
    }
    else if (PL_expect == XOPERATOR) {
        /* binary division */
        s++;
        Mop(OP_DIVIDE);
    }
    else {
        /* else: pattern match */
        ...
        s = scan_pat(s,OP_MATCH);
        TERM(sublex_start());
    }
}
```

The disambiguation is two lines: "if the parser expects an operator,
the `/` is division; otherwise it starts a regex." This is the most
compact case of `PL_expect`-based disambiguation in the entire
tokenizer.

**Chalk grammar-encoding cost:** Low-to-moderate, but tricky. Two
approaches:

1. **Position-based alts** — at positions where `BinaryOp` can fire,
   `/` is division; at positions where an `Atom` can fire, `/` begins
   `RegexLiteral`. The grammar already has `/[*\/%]/` as a
   `BinaryOp` alt and `RegexLiteral` as a `Literal` alt under `Atom`.
   So structurally the grammar *already admits* both; the question is
   whether the Earley parser, with just the grammar, naturally
   prefers one over the other. It does not — recognition produces
   both derivations.

2. **Rewrite `BinaryOp` to exclude `/` and introduce a `DivisionOp`
   terminal matched only after an `Atom`** — this requires
   context-sensitive grammar, which BNF cannot express.

So grammar-encoding doesn't help. The choice genuinely depends on the
left context (an expression preceded the slash → division; no
expression yet → regex), which is exactly what `PL_expect` captures
in Perl.

Rough delta: **0 rules added if we accept current ambiguity; if we
try to grammar-encode, we hit the same context-sensitivity wall as
Class 3.**

**Chalk's current choice:** TypeInference semiring. The type of the
expression expected at this position (Regex vs Num) selects the
derivation. Chalk also restricts bare regex to single lines via the
regex pattern to reduce the set of positions where genuine ambiguity
arises.

**Recommendation:** **Semiring** (unchanged), **with a flag for
perigrin.**

**Reasoning:** This is textbook `PL_expect`-driven disambiguation in
`toke.c`; the grammar cannot encode it. Chalk's choice is correct in
principle.

Flag: The docs say "TypeInference resolves based on the expected type
in context" but the actual `TypeInference.pm` implementation is
signature-validation-heavy; I did not verify end-to-end that
division-vs-regex is the *only* path producing the disambiguation
signal. The `Precedence` semiring's scan-time operator validation
(`Semiring/Precedence.pm:136`) rejects `/` at positions where the
left operand has wrong precedence, which might be doing some of
this work in practice. Confirming which semiring resolves what in
the slash case would be part of the subsequent correctness audit.

---

### Class 5: Named unary vs list operator

**Perl example:**

```perl
defined $x + 1         # named unary: (defined $x) + 1
print $x + 1           # list op: print($x + 1)
push @arr, $x . $y     # list op: push(@arr, $x . $y)
keys %h + 1            # named unary: (keys %h) + 1
```

**Where Perl handles it:** Split across `toke.c` (token emission) and
`perly.y` (precedence).

**In `toke.c`:** the per-keyword switch in `yyl_word_or_keyword`
(`toke.c:7948+`) uses different macros for each keyword:

- `UNI(OP_DEFINED)` at `toke.c:8125` — emits `UNIOP` token.
- `UNI(OP_EXISTS)` at `toke.c:8159`.
- `UNI(OP_LENGTH)`, `UNI(OP_REF)`, `UNI(OP_SCALAR)`, `UNI(OP_EACH)`,
  etc.
- `LOP(OP_PRINT, XREF)`, `LOP(OP_PUSH, XTERM)`,
  `LOP(OP_JOIN, XTERM)`, `LOP(OP_SPLIT, XTERM)`, etc. — emit `LSTOP`
  token.
- `FUN0(OP_TIME)` — emits `FUNC0` token (zero-argument builtins).
- `BLKLOP(OP_MAPSTART)`, `BLKLOP(OP_GREPSTART)`, `BLKLOP(OP_SORT)` —
  emit `BLKLSTOP` (block-first list operator).

So the **keyword-to-arity classification is hardcoded in the
tokenizer per keyword.** There are hundreds of case statements in
the switch.

**In `perly.y`:** separate grammar productions for each token type:

```
listop  :  LSTOP indirob listexpr       /* print $fh @args */
        |  BLKLSTOP block listexpr       /* map { ... } @args */
        |  LSTOP optlistexpr             /* print @args */
        ...

/* No listop production for UNIOP — it appears in the term rule: */
term    :  UNIOP                         /* $_ implied */
        |  UNIOP term                    /* defined $x */
        |  UNIOP block                   /* eval { ... } */
```

(`perly.y:1000-1063`, `perly.y:1391-1395`.)

The precedence table at `perly.y:130,142` gives:

```
%nonassoc LSTOP LSTOPSUB BLKLSTOP    /* very low */
...
%nonassoc UNIOP UNIOPSUB              /* high, between named unary and rel-op */
```

So the tokenizer splits the keyword into one of several token types,
the precedence declarations resolve binding, and separate grammar
alternatives handle the syntactic shape.

**Chalk grammar-encoding cost:** Moderate to high, and interacts
with Class 1.

Approach: classify each builtin as UNARY, LIST, NULLARY, or
BLOCK_LIST at the terminal level (each becomes its own terminal
pattern in the grammar):

```
UnaryBuiltinName ::= /(?:defined|ref|exists|delete|keys|values|...)\b/ ;
ListBuiltinName  ::= /(?:print|push|pop|join|split|...)\b/ ;
BlockListBuiltin ::= /(?:map|grep|sort)\b/ ;
```

Then split `CallExpression` into:

```
CallExpression ::= GeneralCall
                 | UnaryBuiltinCall
                 | ListBuiltinCall
                 | BlockListBuiltinCall ;

UnaryBuiltinCall     ::= UnaryBuiltinName WS Expression
                       | UnaryBuiltinName _ /\(/ _ ExpressionList? _ /\)/ ;
ListBuiltinCall      ::= ListBuiltinName WS ExpressionList
                       | ListBuiltinName _ /\(/ _ ExpressionList? _ /\)/ ;
BlockListBuiltinCall ::= BlockListBuiltin WS Block WS ExpressionList
                       | BlockListBuiltin WS Block
                       | BlockListBuiltin WS ExpressionList
                       | BlockListBuiltin _ /\(/ _ ExpressionList? _ /\)/ ;
```

Rough delta: **3-4 new terminals + ~3 new rules + 8-12 new
alternatives**. Not a multiplicative blowup. But two catches:

1. **The UnaryBuiltinCall precedence.** `defined $x + 1` must parse as
   `(defined $x) + 1`. If `UnaryBuiltinCall ::= UnaryBuiltinName WS
   Expression`, then `Expression` greedily consumes `$x + 1`. The
   grammar alone cannot make `WS Expression` mean "high-precedence
   expression only" without re-introducing the same tiered
   `Expression` structure we rejected in Class 1. So the Precedence
   semiring is still needed for binding. Grammar-encoding the
   **terminal class** of the builtin works; grammar-encoding the
   **binding of its argument** does not.

2. **`TypeInference.pm` and `PrecedenceTable` already carry this
   classification.** Moving it to the grammar duplicates data that
   must currently be maintained in one table. A new builtin addition
   would require *two* places to update instead of one.

**Chalk's current choice:** Precedence semiring, with
`PrecedenceTable` classifying each builtin by arity. Grammar rule
`CallExpression ::= QualifiedIdentifier WS ExpressionList` handles
all forms syntactically; Precedence semiring selects binding.

**Recommendation:** **Semiring** (unchanged), but worth noting this
case is *closer* to grammar-encodable than Classes 2-4.

**Reasoning:** Perl itself splits this in a hybrid way: the tokenizer
does the keyword→token classification (like grammar-encoding), the
grammar has separate productions per token type (like grammar
encoding), but binding is still resolved by the precedence table
(like semiring-resolution). Chalk's flat grammar + Precedence
semiring achieves the same end result with fewer rules, at the cost
of producing more Earley derivations. The grammar-encoded version
*might* be faster (fewer spurious derivations) but doesn't eliminate
the Precedence semiring — so the complexity reduction is minimal
while the grammar-maintenance burden grows. Chalk's choice is
defensible; the reasoning is "delegate the classification table to
one place, not split between grammar and semiring."

Flag: This is the one "admitted ambiguity" where grammar-encoding
is not obviously wrong. If future performance work shows that
Precedence-semiring rejection of list-op-vs-unary-op derivations is
expensive, splitting `CallExpression` by arity class is a viable
optimization.

---

### Class 6: Unary minus vs binary minus

**Perl example:**

```perl
my $x = -5             # unary
my $x = 3 - 2          # binary
my $x = -$y + 3        # unary then binary
my $x = 3 - -$y        # binary then unary
```

**Where Perl handles it:** `toke.c:5880-6000` — `yyl_hyphen`. Key
decision point at `toke.c:5986-6000`:

```c
if (PL_expect == XOPERATOR) {
    ...
    Aop(OP_SUBTRACT);       /* binary */
}
else {
    if (isSPACE(*s) || !isSPACE(*PL_bufptr))
        check_uni();
    OPERATOR(PERLY_MINUS);  /* unary */
}
```

`yyl_hyphen` also handles file-test operators (`-e`, `-r`, etc.,
`toke.c:5882-5952`) and `->` arrow (`toke.c:5963-5985`), and `--`
(`toke.c:5955-5961`). But the core disambiguation is `PL_expect ==
XOPERATOR` → binary, else → unary. Emits separate tokens:
`PERLY_MINUS` for unary, `ADDOP` for binary.

The precedence table at `perly.y:148` gives unary `-` (UMINUS)
very high precedence (between POWOP and PREINC), while binary `-`
(ADDOP) is at `perly.y:145` (much lower).

**Chalk grammar-encoding cost:** Already done! The grammar has two
separate rules:

```
UnaryExpression ::= /!/ _ Expression
    | /-/ _ Expression      # unary minus
    | /\+/ _ Expression
    | /~/ _ Expression
    | /\\/ _ Expression
    | /not\b/ WS Expression ;

BinaryExpression ::= Expression _ BinaryOp _ Expression ;

BinaryOp ::= ...
    | /[+-]/       # binary minus
    | ... ;
```

Grammar-level, the distinction is already encoded: unary `-` at the
start of `UnaryExpression`, binary `-` in `BinaryOp`. What the
grammar *cannot* encode is the **position-based choice**: when the
Earley parser is at a position where *both* `UnaryExpression` and
`BinaryExpression` could start, it produces both derivations.

So the actual ambiguity is not "does `-` mean unary or binary" (the
grammar encodes that) but "at *this* position, is an `Expression`
expected (→ `UnaryExpression` starts) or a `BinaryOp` expected (→
continuation of `BinaryExpression`)?" This is `PL_expect ==
XOPERATOR` again.

Rough delta: **0 rules**. Grammar cannot encode the position-based
choice without full context sensitivity.

**Chalk's current choice:** Precedence semiring (per docs, "with help
from grammar structure"). The grammar already has the unary vs
binary split; the Precedence semiring's `_scan_multiply` rejects
`-` as `BinaryOp` when the left operand's precedence context doesn't
permit it.

**Recommendation:** **Semiring** (unchanged).

**Reasoning:** The grammar does encode the unary/binary split (two
separate rules with `-` in each). What remains ambiguous is
*position* — same as Class 4 (slash). Perl resolves this via
`PL_expect`; Chalk resolves it via the Precedence semiring consulting
the left operand's accumulated precedence context. This is the
correct semiring layer and the docs' phrasing ("with help from
grammar structure") is accurate. Chalk's choice is correct.

---

### Class 7: map/grep/sort BLOCK vs EXPR form

**Perl example:**

```perl
map { $_->name } @items         # block form
map name => $_, @items          # expr form
sort { $a <=> $b } @items       # block form
sort @items                     # no block
grep { defined $_ } @items      # block form
grep defined($_), @items        # expr form
```

**Where Perl handles it:** Hybrid. `toke.c` classifies the builtin
name via `BLKLOP(OP_MAPSTART)` etc. (`toke.c:8016`, `8025` for
`all`/`any`, and similar for `map`, `grep`, `sort`). This emits
token `BLKLSTOP`, which has its own production in `perly.y:1004`:

```
|       BLKLSTOP block listexpr /* all/any { ... } @args */
                { $$ = op_convert_list($BLKLSTOP, OPf_STACKED,
                        op_prepend_elem(OP_LIST, newUNOP(OP_NULL, 0, op_scope($block)), $listexpr) );
                }
```

Plus the regular `LSTOP indirob listexpr` production at
`perly.y:1000` handles `map EXPR, @args`. The grammar *does* have
two productions (block form and expr form), gated by the token
class.

**Chalk grammar-encoding cost:** Moderate. The grammar already has:

```
CallExpression ::= QualifiedIdentifier _ /\(/ _ ExpressionList? _ /\)/
    | QualifiedIdentifier WS ExpressionList
    | QualifiedIdentifier WS Block WS ExpressionList    # block-first
    | QualifiedIdentifier WS Block ;                     # block-only
```

To match Perl's approach, we'd introduce a distinct terminal:

```
BlockListBuiltin ::= /(?:map|grep|sort)\b/ ;
RegularBuiltin   ::= /[a-zA-Z_]\w*(?:::[a-zA-Z_]\w*)*/ ;  # all others

CallExpression ::= BlockListBuiltin WS Block WS ExpressionList
    | BlockListBuiltin WS Block
    | BlockListBuiltin WS ExpressionList
    | RegularBuiltin _ /\(/ _ ExpressionList? _ /\)/
    | RegularBuiltin WS ExpressionList ;
```

Rough delta: **+1 terminal, split `CallExpression` alts from 4 to 5,
and need to special-case `QualifiedIdentifier` to not match when
it's map/grep/sort (negative lookahead or ordered alternative)**.

Catches:

1. The Block-vs-Hash ambiguity (Class 3) still exists for the `{...}`
   inside `BlockListBuiltin WS Block WS ExpressionList`. Structural
   semiring is still needed there.

2. As the Option B postmortem document showed, renumbering
   `CallExpression` alts breaks `Structural.pm`'s alt-index-based
   preference rules. Any grammar refactor in this area carries
   significant rework cost in the semirings.

3. The `map name => $_, @items` form (EXPR form) produces an
   `ExpressionList` that doesn't start with `{`. The grammar already
   admits this via `QualifiedIdentifier WS ExpressionList`. Making
   `BlockListBuiltin WS ExpressionList` distinct from
   `RegularBuiltin WS ExpressionList` doesn't eliminate any
   ambiguity — they're both `CallExpression`. Their only difference
   is whether the callee name is one of map/grep/sort.

**Chalk's current choice:** Structural (for block/hash distinction
of the `{...}`) + Precedence (for argument binding). Grammar
admits all four shapes of `CallExpression`; semirings pick.

**Recommendation:** **Semiring** (unchanged), but weaker conviction
than Classes 2-6.

**Reasoning:** Perl grammar-encodes this via a dedicated token
(`BLKLSTOP`) emitted by the tokenizer's per-keyword classification.
Chalk could do the same with a dedicated `BlockListBuiltin` terminal
and a dedicated `CallExpression` alt. The cost would be bounded
(~3 alt changes, 1 new terminal), and it would eliminate one
semiring-decided branch.

However: the grammar refactor would renumber `CallExpression` alts,
which (per the April 24 postmortem) costs at least four semiring
site rewrites and caused test failures last time it was attempted.
And the Block-vs-Hash distinction (Class 3) inside the block-form
still requires Structural semiring. So the grammar-encode saves
limited complexity while risking regression.

Keeping this in the semiring layer is defensible for the same reason
Chalk keeps Class 5 there: the classification is already in
`PrecedenceTable` and `TypeInference`, and duplicating into the
grammar creates two sources of truth.

Flag: if Class 5 is ever grammar-encoded (splitting `CallExpression`
by builtin arity class), Class 7 should be grammar-encoded in the
same pass — they share the same refactor.

---

### Class 8: Indirect object heuristics (EXCLUDED)

**Perl example:**

```perl
new Foo              # indirect object: Foo->new
new Foo @args        # indirect: Foo->new(@args)
new(Foo)             # function call: new(Foo)
my $x = new Foo      # indirect
```

**Where Perl handles it:** `toke.c:4773-4852` — `S_intuit_method` is
the big heuristic. Highlights:

```c
/*
 * Does all the checking to disambiguate
 *   foo bar
 * between foo(bar) and bar->foo.  Returns 0 if not a method, otherwise
 * METHCALL (bar->foo(args)) or METHCALL0 (bar->foo args).
 *
 * Not a method if foo is a filehandle.
 * Not a method if foo is a subroutine prototyped to take a filehandle.
 * Not a method if it's really "Foo $bar"
 * Method if it's "foo $bar"
 * Not a method if it's really "print foo $bar"
 * Method if it's really "foo package::" (interpreted as package->foo)
 * Not a method if bar is known to be a subroutine ("sub bar; foo bar")
 * Not a method if bar is a filehandle or package, but is quoted with
 *   =>
 */
STATIC int S_intuit_method(pTHX_ char *start, SV *ioname, CV *cv) {
    ...
    if (!FEATURE_INDIRECT_IS_ENABLED)
        return 0;
    ...
    if (cv && SvPOK(cv)) { /* check prototype */ ... }
    if (*start == '$') { ... }
    s = scan_word(s, tmpbuf, sizeof tmpbuf, TRUE, &len);
    if (!keyword(tmpbuf, len, 0)) {
        if (len > 2 && tmpbuf[len - 2] == ':' && tmpbuf[len - 1] == ':') {
            len -= 2; tmpbuf[len] = '\0';
            goto bare_package;
        }
        indirgv = gv_fetchpvn_flags(tmpbuf, len, ...);
        ...
        /* filehandle or package name makes it a method */
        if (!cv || GvIO(indirgv) || gv_stashpvn(...)) {
            ...
            return *s == '(' ? METHCALL : METHCALL0;
        }
    }
    return 0;
}
```

This is stateful, symbol-table-aware (checks `gv_fetchpvn_flags` —
actual package/IO existence in the running interpreter), and even
optional (`no feature 'indirect'` disables it entirely). It cannot
be expressed in BNF — it consults runtime data structures.

Modern Perl has moved against indirect object notation. Perl 5.36+
disables it by default (`use feature 'indirect'` is needed to turn
it back on), and the feature is deprecated and scheduled for
removal.

**Chalk grammar-encoding cost:** N/A (the decision is to restrict
out, not to encode).

If Chalk *did* want to accept indirect syntax, the grammar would have
to admit `new Foo` as both (a) a call `new(Foo)` and (b) a method
call `Foo->new`. The disambiguation then requires symbol-table
lookups that Chalk's compile-time pipeline doesn't perform (it's a
compiler, not an interpreter with a populated symbol table). The
only grammar-level workaround is to arbitrarily prefer one reading,
which silently changes program semantics compared to Perl.

**Chalk's current choice:** **Excluded.** `docs/chalk-grammar-spec.md:46`
lists "Indirect object syntax (`new Foo`) — ambiguous parsing" as
excluded. The grammar does not accept `new Foo` as a method call; it
parses as `CallExpression ::= QualifiedIdentifier WS ExpressionList`,
which would be `new(Foo)` (a function call taking `Foo` as a bareword
argument). In Chalk's subset, barewords as function arguments are
already restricted, so this is likely rejected somewhere downstream.

**Recommendation:** **Restrict** (unchanged).

**Reasoning:** Perl does this via runtime symbol-table lookup, a
mechanism Chalk fundamentally lacks. There is no grammar encoding
and no reasonable semiring approximation. Deprecating the feature
aligns with upstream Perl's direction (5.36 disabled it by default).
Chalk's choice is correct and is the only viable choice for a
compile-time static analyzer.

---

### Class 9: Bareword heuristics (RESTRICTED)

**Perl example:**

```perl
print STDOUT "hello"           # STDOUT is a filehandle bareword
print FH $x                    # FH is a filehandle bareword
my %h = (foo => 1);            # 'foo' is a bareword hash key (quoted via =>)
$h{foo}                        # 'foo' is an autoquoted bareword hash key
sub foo {}                     # 'foo' is a subroutine name
LOOP: for (...) { last LOOP }  # LOOP is a label
Foo::Bar->method()             # 'Foo::Bar' is a class name
```

**Where Perl handles it:** Distributed across many places in `toke.c`:

1. **Bareword filehandles** (`STDOUT`, `FH`): recognized via
   `PL_last_lop_op == OP_PRINT` / `OP_PRTF` / `OP_SAY` / etc. at
   `toke.c:7671-7679`:

   ```c
   if ((PL_last_lop_op == OP_PRINT
           || PL_last_lop_op == OP_PRTF
           || PL_last_lop_op == OP_SAY
           || PL_last_lop_op == OP_SYSTEM
           || PL_last_lop_op == OP_EXEC)
       && (PL_hints & HINT_STRICT_SUBS))
   {
       pl_yylval.opval->op_private |= OPpCONST_STRICT;
   }
   ```

   And via the `OA_FILEREF` arg-type flag at `toke.c:7803`:

   ```c
   || ((PL_opargs[PL_last_lop_op] >> OASHIFT)& 7) == OA_FILEREF
   ```

2. **Hash keys via fat-arrow (autoquoting)**: `toke.c:7849-7865`:

   ```c
   /* Is this a word before a => operator? */
   if (*s == '=' && s[1] == '>' && !pkgname) {
       ...
       TERM(BAREWORD);
   }
   ```

3. **Hash keys inside `{...}`** — `$h{foo}` — autoquoted only if a
   single bareword-plus-close-brace: handled inside `yyl_leftcurly`
   (`toke.c:6338-6356`), which scans ahead for `bareword }`.

4. **Subroutine names**: `toke.c:8051+` for `KEY_class`, `KEY_sub`
   etc. — all use `force_word(s, BAREWORD, ...)`.

5. **Labels**: `toke.c:9060-9068`:

   ```c
   if (!anydelim && PL_expect == XSTATE
         && d < PL_bufend && *d == ':' && *(d + 1) != ':') {
       ...
       TOKEN(LABEL);
   }
   ```

6. **Class names**: Implicit in `S_intuit_method` and the standard
   bareword handling; `Foo::Bar` is recognized because `::` is a
   package-name separator in `QualifiedIdentifier`.

This is a *family* of heuristics, not one. Each subcase has its own
context trigger (previous token, lookahead, feature flags).

**Chalk grammar-encoding cost:** Variable by subcase.

- **Hash keys**: Chalk requires quoting (the current grammar's
  `HashConstructor ::= /\{/ _ ExpressionList? _ /\}/` only allows
  expressions, not barewords — though `foo => ...` works because
  `QualifiedIdentifier` matches `foo` and `=>` is a list separator).
  Cost to extend: would need a dedicated `HashKey ::= StringLiteral
  | Variable | QualifiedIdentifier` and rewrite `HashConstructor` /
  `ExpressionList` to distinguish "key position" from "value
  position". Rough delta: **+1 rule, touch 2 rules**. Feasible but
  semantically tricky (autoquoting works only in specific positions).

- **Filehandles**: Chalk excludes them. Adding them back would
  require a `Filehandle` terminal (uppercase-only identifier?) and
  splitting `print` / `say` / etc. into dedicated grammar rules
  that accept an optional filehandle argument:
  `PrintCall ::= /print\b/ WS Filehandle WS ExpressionList | ...`.
  Rough delta: **~1 new terminal, ~6 new rule alts per filehandle-
  accepting builtin (print, say, warn, printf, sprintf, system,
  exec)**, i.e. ~42 alts. This is a significant grammar extension.

- **Labels**: Not yet supported in Chalk. Cost to add:
  `StatementItem ::= LabelPrefix? StatementItem_inner ;` and
  `LabelPrefix ::= QualifiedIdentifier _ /:/ _ ;`, plus `LOOPEX`
  variants (`last LABEL`, `next LABEL`, `redo LABEL`) in
  `SimpleStatement`. Rough delta: **+2 rules**. Bounded.

- **Class names**: Already handled by `QualifiedIdentifier`.
  `Foo::Bar->method()` parses as
  `MethodCall (QualifiedIdentifier, QualifiedIdentifier, args)`.

- **Function names**: Already handled by `QualifiedIdentifier` via
  `CallExpression`.

So "bareword" is a grab-bag. Some subcases cost nothing (function
names, class names — grammar already handles them). Some cost a
few rules (hash keys, labels). Some are expensive and inherit Perl's
stateful recognition logic (filehandles).

**Chalk's current choice:** **Restricted.** Per the docs:

- Hash keys must be quoted.
- Filehandles are not barewords (Chalk doesn't support the classical
  `print FH ...` syntax).
- Labels not yet supported.
- Function names, class names: handled as `QualifiedIdentifier`.

**Recommendation:** **Restrict (partial)**, **with clarifications**.

- **Class names, function names**: already grammar-encoded via
  `QualifiedIdentifier` — these aren't really "restricted", they're
  grammar-encoded.
- **Hash keys**: restricted (quoting required). Grammar-encoding
  autoquoting (`{foo}` → `{'foo'}`) is feasible (~+1-2 rules) but
  has semantic subtleties (autoquoting-must-be-single-word). The
  current restriction is correct for a simple subset; future
  extension is possible if needed.
- **Filehandles**: restricted entirely. This is correct — supporting
  filehandles requires either accepting them as barewords (distinct
  grammar rule) or using file-handle objects (which Chalk can do
  via `IO::File` or similar). A principled deprecation.
- **Labels**: currently not supported. Adding them is a bounded
  grammar change (+2 rules). Not a decision this record must make,
  but note the path.

**Reasoning:** Perl's bareword handling is a family of stateful
tokenizer heuristics, each keyed to a specific context. Chalk's
chosen subset (static classes, no filehandle barewords, quoted hash
keys, no labels yet) removes the subcases that require stateful
tokenizer support and keeps the ones that are cleanly grammar-
encodable (class/function names). This is a principled partitioning
— not a single uniform restriction. The documentation phrasing
("Bareword resolution — Chalk restricts this: hash keys must be
quoted, filehandles are not barewords, labels are not yet
supported") reflects this.

Flag: the docs currently enumerate the subcases as "Bareword
resolution (filehandle vs class name vs function vs hash key vs
label)". The wording implies one ambiguity; it's actually five
distinct mechanisms in `toke.c`, and Chalk handles them
differently. Consider rewriting the entry to make the partitioning
explicit.

---

## Summary table

| # | Name | Perl's mechanism | Grammar cost | Current | Recommended | Changed? |
|---|---|---|---|---|---|---|
| 1 | Precedence | `perly.y:123-155` bison precedence table | Very high (~+23 rules) | Semiring | Semiring | No |
| 2 | Keyword vs identifier | `toke.c:7946+` switch + `toke.c:7849` fat-arrow lookahead + `toke.c:9060` label lookahead | Moderate, fails on fat-arrow | Semiring | Semiring | No |
| 3 | Block vs hash `{}` | `toke.c:6320-6520` `PL_expect` + fallback heuristics | Impossible without restructure; requires pre-lex context | Semiring | Semiring | No |
| 4 | `/` division vs regex | `toke.c:6733-6763` `PL_expect` (2-line decision) | 0 (grammar already has both; position is ambiguous) | Semiring | Semiring | No |
| 5 | Named unary vs list op | `toke.c:7948+` per-keyword `UNI`/`LOP`/`FUN0` + `perly.y:1000-1047` distinct productions | Moderate (+3 terminals, +3 rules, +8-12 alts) | Semiring | Semiring | No (borderline) |
| 6 | Unary vs binary `-` | `toke.c:5986-6000` `PL_expect == XOPERATOR` | 0 (grammar already split; position ambiguous) | Semiring | Semiring | No |
| 7 | map/grep/sort BLOCK vs EXPR | `toke.c` emits `BLKLSTOP` token + `perly.y:1004` dedicated production | Moderate (+1 terminal, ~3 alt changes); risky renumber | Semiring | Semiring | No (weakly) |
| 8 | Indirect object | `toke.c:4773-4852` `S_intuit_method` + runtime symbol table | N/A | Excluded | Excluded | No |
| 9 | Bareword heuristics | Distributed: `toke.c:7671` (filehandle); `toke.c:7849` (fat-arrow); `toke.c:6338` (hashkey); `toke.c:8051+` (sub names); `toke.c:9060` (label) | Subcases vary: 0 to very high | Partial (mix of grammar + restrict) | Partial (clarify partitioning) | No |

No recommended changes; all current classifications are correct.
Clarifications recommended for docs (classes 4, 9).

## Key findings

1. **Every "admitted ambiguity" in Chalk maps directly to `PL_expect`
   or a per-keyword tokenizer classification in `toke.c`.** Chalk's
   semirings are the Earley-native equivalent of Perl's stateful
   tokenizer logic — they read the same signal (what does the
   enclosing position expect?) and take the same action (reject the
   wrong interpretation). This is a principled correspondence, not
   coincidence.

2. **Classes 3, 4, 6 are grammatically undecidable without full
   context sensitivity.** These cases have zero grammar-encoding
   cost available — the grammar already has both alternatives, and
   the remaining ambiguity is purely positional. `PL_expect` is the
   minimum state required; no BNF fix exists. Chalk's choice of
   semiring for these three is not just "defensible", it's forced.

3. **Class 1 is the paradigm case of rule-explosion avoidance.**
   Grammar-encoding Perl's precedence would require ~24 tiered
   expression nonterminals. Bison sidesteps this with an external
   precedence table, and Chalk does the same with the Precedence
   semiring. These are structurally identical mechanisms.

4. **Classes 5 and 7 are the only "admitted ambiguities" that could
   plausibly be grammar-encoded.** Both cost ~1-3 terminals + 3-10
   rule alts. The cost is bounded, not multiplicative. The decision
   to leave them in the semiring layer is defensible (single source
   of truth in `PrecedenceTable`/`TypeInference`, no duplication) but
   is the closest call in the nine. If performance-driven grammar
   restructure is ever warranted, these are the two to move first.

5. **Class 2 (keyword vs identifier) requires the semiring in the
   fat-arrow case specifically.** A negative-lookahead regex for
   non-keyword identifiers can cover most cases, but fat-arrow
   (`class => ...`) requires the keyword to be *admitted* as an
   identifier in one specific context. No BNF encoding handles this
   without context sensitivity. Chalk's "is the consuming rule
   predicted here?" check is exactly the Earley-native equivalent of
   `PL_expect`-aware keyword recognition.

6. **Class 8 is the only exclusion that cannot be grammar-encoded in
   principle.** `S_intuit_method` consults the runtime symbol table
   (`gv_fetchpvn_flags`) — package/IO existence in the running
   interpreter. Chalk, as a compile-time static analyzer, cannot
   reproduce this signal. Exclusion is the only viable option, and
   it aligns with modern Perl's deprecation direction.

7. **Class 9 (bareword handling) is not one ambiguity but five.**
   The docs' phrasing collapses them. Chalk handles each subcase
   differently: function/class names are grammar-encoded (via
   `QualifiedIdentifier`), hash keys are restricted (quoting
   required), filehandles are restricted entirely, labels are
   not-yet-supported. The "restrict" label is accurate but
   undersells the grammar work already done.

8. **The April 24 grammar-refactor postmortem is cautionary
   evidence.** Attempting to eliminate a small pseudo-ambiguity
   (single-element `ExpressionList`) by restructuring the grammar
   required touching four semiring sites because `Structural.pm` and
   `TypeInferenceActions.pm` key their disambiguation on
   `(rule_name, alt_idx)`. Any grammar-encoding move that renumbers
   alternatives carries this hidden cost. This reinforces the
   recommendation to leave classes 5 and 7 in the semiring layer
   even though they're technically grammar-encodable.

9. **Perl itself uses a hybrid approach.** Precedence is outside
   the grammar (bison's `%left`/`%right`). Keyword arity is
   grammar-encoded (separate `UNIOP`/`LSTOP`/`BLKLSTOP` tokens).
   Block-vs-hash is inside the tokenizer (stateful). Each class is
   handled at the layer best suited to it. Chalk collapses the
   tokenizer and grammar layers into "grammar + Earley recognizer"
   and recovers the stateful disambiguation via semirings — a
   structurally equivalent hybrid, just drawn at different
   boundaries.

## Questions for the maintainer

1. **Class 4 / division-vs-regex — which semiring actually does the
   resolution?** The docs say `TypeInference`. Reading the code,
   `Precedence.pm:_scan_multiply` also does scan-time operator
   validation that would reject `/` at wrong-precedence positions.
   Is `TypeInference` the sole resolver, or is `Precedence` doing
   some of the work in practice? The correctness audit (Phase 2 of
   this decision-record work) will need to know which semiring owns
   this.

2. **Class 5 and 7 — are we comfortable leaving them in the semiring
   layer long-term?** The analysis above marks both as "borderline"
   — grammar-encoding is bounded, not explosive. The current choice
   is defensible (single source of truth for the builtin-arity
   table) but not forced. If we're planning future grammar
   refactors, these are the two to consider. If we're not, keeping
   them in the semiring is fine.

3. **Class 7 vs the April 24 postmortem.** The postmortem suggests
   grammar-refactors that touch `CallExpression` alt numbering are
   costly (4+ semiring sites break). Should we document this as a
   discipline rule — "don't grammar-refactor `CallExpression`
   without budgeting for semiring site rework" — or as an
   architectural invariant (the grammar's `CallExpression` shape is
   load-bearing for semiring correctness and should be frozen)?

4. **Class 9 — should the docs be split?** The "Bareword resolution"
   entry in `ambiguity-classes.md` is a single bullet that actually
   enumerates five distinct mechanisms with different dispositions.
   My suggestion is to split it into sub-entries (9a Filehandles
   excluded, 9b Hash keys restricted to quoted form, 9c Labels not
   yet supported, 9d Function/class names grammar-encoded via
   `QualifiedIdentifier`) but that's a docs change, and I haven't
   made it. Is that worth doing as part of the audit follow-up?

5. **Anything I missed?** I did not audit the complete `toke.c` for
   subcases not mentioned in the docs (e.g. string-eval edge cases,
   heredoc parsing, prototype-driven parsing, `__END__`/`__DATA__`
   handling). I treated the docs' nine classes as the complete list
   of points needing decisions. If there are other disambiguation
   points that belong in this record, say so and I'll audit them in
   a follow-up pass.
