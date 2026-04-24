# Toke.c Sweep: Disambiguation Points Not Covered by the Nine Documented Classes

**Status:** Read-only report.
**Date:** 2026-04-24.
**Scope:** A systematic sweep of `perl5/toke.c` (14068 lines)
looking for tokenizer disambiguation points that are NOT already
documented in `docs/architecture/ambiguity-classes.md` or the
`2026-04-24-ambiguity-decision-record.md`.

## Overview

Perl's `toke.c` is a 14000-line stateful tokenizer. It resolves
ambiguity at three levels:

1. **`PL_expect`** — an explicit state machine (XTERM, XOPERATOR,
   XBLOCK, XSTATE, XREF, XPOSTDEREF, XATTRBLOCK, XATTRTERM,
   XTERMBLOCK, XBLOCKTERM, XTERMORDORDOR) that determines whether
   the next token should be a term or an operator (and, in various
   sub-states, what kind).
2. **Per-keyword classification** — the big switch in
   `yyl_word_or_keyword` (`toke.c:7946-8897`) uses different token
   macros (`UNI`, `UNIDOR`, `LOP`, `BLKLOP`, `FUN0`, `UNIBRACK`,
   `UNIOP`, `LSTOP`, `FUNC0`, `FUNC0OP`) to emit dedicated token
   types per keyword. These are the "FUN1/UNI vs LOP" distinctions
   called out in the existing docs.
3. **`PL_lex_state`** (LEX_NORMAL, LEX_INTERPNORMAL,
   LEX_INTERPCASEMOD, LEX_INTERPPUSH, LEX_INTERPSTART,
   LEX_INTERPEND, LEX_INTERPENDMAYBE, LEX_INTERPCONCAT,
   LEX_INTERPCONST) — a separate state machine for string
   interpolation contexts. String insides are tokenized
   differently than normal code.

The nine classes in `ambiguity-classes.md` capture the **most
visible** disambiguation points. This report identifies
disambiguation points that fall outside them.

**Coverage estimate:** I read the top-level structure of the file
(all `S_*`/`yyl_*` function signatures), then drilled into the
per-character dispatch functions (`yyl_dollar`, `yyl_hyphen`,
`yyl_plus`, `yyl_star`, `yyl_percent`, `yyl_caret`, `yyl_colon`,
`yyl_leftcurly`, `yyl_rightcurly`, `yyl_ampersand`,
`yyl_verticalbar`, `yyl_bang`, `yyl_snail`, `yyl_slash`,
`yyl_leftsquare`, `yyl_leftpointy`, `yyl_sglquote`, `yyl_dblquote`,
`yyl_backtick`, `yyl_backslash`), the keyword dispatch
(`yyl_word_or_keyword`, `yyl_sub`, `yyl_my`, `yyl_do`, `yyl_foreach`,
`yyl_require`), the intuition functions (`S_intuit_method`,
`S_intuit_more`, `S_pending_ident`, `S_postderef`), the scanning
functions (`S_scan_str`, `S_scan_pat`, `S_scan_subst`,
`S_scan_trans`, `S_scan_heredoc`, `S_scan_inputsymbol`,
`S_scan_formline`, `S_scan_num`, `S_scan_ident`,
`S_scan_vstring`), and the top-level `Perl_yylex`. I read the
`LEX_INTERP*` handling and relevant snippets. Roughly 1500-2000
lines read in detail, with targeted searches filling in gaps.
I make no claim of completeness — the obscurer corners of
`scan_const` (string escape handling) and `S_tokeq` were only
skimmed. But I'm confident the **structurally significant**
disambiguation points are captured.

## Methodology

- Listed all `S_*` / `yyl_*` function definitions with grep.
- Read `Perl_yylex` (the main entry point) and traced dispatch
  to per-character functions.
- Read each `yyl_*` function whose logic might encode a
  disambiguation.
- For each candidate, asked: *does the same token sequence admit
  two different interpretations?* If yes, this is an ambiguity.
  If "just complex parsing with one interpretation per position",
  skipped it. For example, `scan_const` processing escape
  sequences is complex but not ambiguous.
- Checked each candidate against the nine classes; if it clearly
  maps to one, listed briefly and moved on.
- For non-matches, traced Chalk's grammar to see whether the
  feature is admitted at all, then traced Chalk's semirings if
  it is.

**Distinguishing ambiguity from complexity:** I focused on cases
where the *same character sequence* could produce different
parse trees. Mechanisms that are just elaborate — string
interpolation sublexing, escape processing, bracket matching —
are not ambiguity points per se. But the **boundaries** of those
mechanisms (when does interpolation start/stop? when is a `{`
a subscript inside `"$h{k}"` vs a literal brace?) *are* ambiguity
points.

## Points already covered by the nine documented classes

The following `toke.c` sites clearly map to one of Classes 1-9
from `ambiguity-classes.md`. No re-analysis.

- `toke.c:6733-6763` `yyl_slash` — Class 4 (slash vs regex).
- `toke.c:5986-6000` `yyl_hyphen` PL_expect branch — Class 6
  (unary vs binary minus).
- `toke.c:6015-6029` `yyl_plus` — Class 6 (unary vs binary plus).
- `toke.c:6320-6526` `yyl_leftcurly` — Class 3 (block vs hash).
- `toke.c:6338-6356` bareword-hash-key autoquoting inside `{...}`
  — Class 9 (bareword heuristics; autoquoted hash key).
- `toke.c:7849-7865` fat-arrow autoquoting in `yyl_just_a_word` —
  Class 2/9 (keyword-vs-identifier, bareword hash key).
- `toke.c:4773-4852` `S_intuit_method` — Class 8 (indirect
  object, excluded).
- `toke.c:7671-7679` filehandle bareword detection — Class 9.
- `toke.c:7946+` keyword switch `UNI` vs `LOP` vs `BLKLOP` vs
  `FUN0` — Class 5 (named unary vs list op) and Class 7
  (map/grep/sort BLKLOP).
- `toke.c:9060-9068` label detection — Class 9 (label subcase).
- `toke.c:8048-8055` `KEY_class` dispatch — Class 2.

## Previously undocumented points

### Point 10: `-X` file test operators vs unary minus plus bareword

**Perl example:**
```perl
-e $filename           # file test: does $filename exist?
-e $x + 1              # file test (unary), equivalent to (-e $x) + 1
-eFOO;                 # file test? or unary minus and bareword 'eFOO'?
-foo                   # unary minus of bareword 'foo' (string)
-foo(@args)            # unary minus of function call foo(...)
-d                     # file test on $_ (named unary, implicit arg)
-d $dir                # file test on $dir
```

**toke.c citation:** `toke.c:5882-5952` — `yyl_hyphen` starts with:
```c
if (s[1] && isALPHA(s[1]) && !isWORDCHAR(s[2])) {
    /* '-X' pattern: minus, one letter, non-word — candidate file test */
    ...
    switch (tmp) {
    case 'r': ftst = OP_FTEREAD;    break;
    ...
    }
}
```
Only 23 single-letter followers (`r`, `w`, `x`, `o`, `R`, `W`, `X`,
`O`, `e`, `z`, `s`, `f`, `d`, `l`, `p`, `S`, `u`, `g`, `k`, `b`,
`c`, `t`, `T`, `B`, `M`, `A`, `C`) are file-test operators. `-r $x`
is a file test; `-f(@args)` is a file test; but `-foo` is unary
minus applied to bareword `foo`. The disambiguation is: `-` followed
by `[rwxoRWXOezsfdlpSugkbctTBMAC]` followed by a non-word-char is a
file test; otherwise `-` is unary minus.

Additionally (line 5893), if the tokenizer sees `-X` that *looks*
like a file test but is actually followed by `=>` (e.g.
`-r => 1`), it backs off to unary minus.

**Nature of the ambiguity:** `-e $x` could mean (a) file test
"exists" applied to `$x`, or (b) unary minus applied to bareword
`e` followed by scalar `$x` (which would then need a binary
operator in between for a valid parse). Perl picks (a) whenever
the single-letter is in the file-test set and the third char
isn't a word char.

**Does Chalk support the feature?** No. `docs/chalk-bootstrap.bnf`
has no FileTestOp rule, no `-X` terminal. Grep confirms neither
"FTST" nor file-test letter patterns in the grammar or semirings.

**Recommended disposition:** **not-yet-supported**; if added:
**grammar** (via dedicated terminal). The set of file-test
letters is a bounded table (23 letters); a single terminal
`/-[rwxoRWXOezsfdlpSugkbctTBMAC]\b/` could match them, with
`FileTestExpression ::= FileTestOp WS Expression` as a new
rule. This is purely token-shape, no semantic layering needed.

- **Rule-explosion test:** No — one terminal, one rule.
- **Layer-violation test:** No — the distinction is textual.

Grammar is the right layer.

---

### Point 11: `sub NAME (...)` prototype vs signature

**Perl example:**
```perl
sub foo ($$) { }               # prototype: $ and $ required scalars
sub foo ($x, $y) { }           # signature (when use feature 'signatures')
method foo ($x, $y) { }        # signature (always, for method)
```

**toke.c citation:** `toke.c:5539-5615` — `yyl_sub`:
```c
bool is_sigsub = is_method || FEATURE_SIGNATURES_IS_ENABLED;
...
/* Look for a prototype */
if (*s == '(' && !is_sigsub) {
    s = scan_str(s,FALSE,FALSE,FALSE,NULL);
    ...
    have_proto = TRUE;
    ...
}
```
The `(` after a sub name is parsed as a prototype *unless*
signatures are enabled (via `use feature 'signatures'` or
implicit-for-method). Signature parsing is then done by
`yyl_sigvar` (`toke.c:5229+`). `method` always uses signatures.

**Nature of the ambiguity:** The character sequence `sub foo ($x)`
parses as either (a) prototype declaration with one parameter of
prototype `$x`, which is syntactically meaningless as prototypes
only use sigil characters, or (b) signature declaring scalar
parameter `$x`. The tokenizer commits one way based on the
signatures feature flag, which is a compile-time pragma.

**Does Chalk support the feature?** Partially. The grammar has:
```bnf
Signature ::= /\(/ _ /\)/ | /\(/ _ SignatureParams _ /\)/ ;
SubroutineDefinition ::= /sub\b/ WS QualifiedIdentifier _ Signature? _ Block
```
Only signatures are parsed; there is **no grammar production for
prototypes**. Chalk assumes signatures-always (matching method
semantics). Prototypes are effectively excluded.

**How Chalk handles it today:** By exclusion. `sub foo ($$) {}`
would either fail to parse (if `$$` is invalid as a signature
param — which it is per `yyl_sigvar:5248` checks) or be mis-parsed.
I did not verify the exact failure mode but confirmed Chalk has
no `Prototype` grammar rule.

**Recommended disposition:** **exclude** (current state; document
it). Prototypes are deprecated-ish in modern Perl, rarely used
in new code, and conflict with signatures (Perl itself handles
them via the `use feature` pragma — not feasible in a static
compiler without modeling pragma state).

- **Rule-explosion test:** No.
- **Layer-violation test:** Yes — Perl's decision depends on
  runtime feature-flag state. Chalk would have to model the
  pragma state to disambiguate, which is exactly the kind of
  stateful context the architecture is trying to avoid.

Document as excluded (alongside indirect object, Class 8).

---

### Point 12: Prototype-driven parsing of user-declared subs

**Perl example:**
```perl
sub mymax ($$) { ... }
mymax 1, 2         # binary: prototype $$ says two scalar args
mymax(1, 2)        # function call: parens override

sub myif (&$) { ... }
myif { ... } $x    # block-first: prototype &$ makes it blocklop-like
```

**toke.c citation:** `toke.c:6265-6317` — `yyl_subproto`:
```c
if ((*proto == '$' || *proto == '_' || *proto == '*' || *proto == '+')
    && proto[1] == '\0')
{
    UNIPROTO(UNIOPSUB, optional);
}
...
if (*proto == '&' && *s == '{') {
    PREBLOCK(LSTOPSUB);
}
```
When the tokenizer resolves a bareword to a known CV with a
prototype, it inspects the prototype string to decide what token
type to emit: `UNIOPSUB` (named-unary-like), `FUNC0SUB` (nullary),
`LSTOPSUB` (list-op-like), `PREBLOCK` (block-first). This is
*the* mechanism that makes user-defined `mymax $a, $b` parse
like `push @arr, $x`.

**Nature of the ambiguity:** The same bareword call can bind
arguments different ways depending on the CV's prototype. `foo
$a + 1` might be `foo($a) + 1` (if `foo` has `$` prototype) or
`foo($a + 1)` (if `foo` has `$;$` prototype, taking `$a+1` as
first arg) or a generic list call (if no prototype).

**Does Chalk support the feature?** No. Chalk has no prototype
grammar (see Point 11). All user sub calls parse as
`CallExpression ::= QualifiedIdentifier WS ExpressionList` (list
operator shape). This may produce incorrect binding for calls to
prototyped subs in real Perl source, but since Chalk also doesn't
honor prototype declarations, the compile is internally
consistent.

**Recommended disposition:** **exclude** (unchanged). Prototypes
require runtime symbol-table lookup (the prototype comes from the
CV, which exists only at runtime in Perl's model). For the same
reason Class 8 is excluded, user-defined prototypes are
excluded. Document explicitly.

- **Rule-explosion test:** N/A.
- **Layer-violation test:** Yes, severely — needs runtime
  symbol-table access.

---

### Point 13: `eval BLOCK` vs `eval STRING`

**Perl example:**
```perl
eval { die "x" }       # block form: catches die
eval "1 + 2"           # string form: compiles and runs string
eval $code             # string form with a scalar
```

**toke.c citation:** `toke.c:8164-8173`:
```c
case KEY_eval:
    s = skipspace(s);
    if (*s == '{') {
        PL_expect = XTERMBLOCK;
        UNIBRACK(OP_ENTERTRY);    /* block form */
    }
    else {
        PL_expect = XTERM;
        UNIBRACK(OP_ENTEREVAL);   /* string form */
    }
```
One-character lookahead decides.

**Nature of the ambiguity:** `eval` followed by `{` is the block
form; `eval` followed by anything else is the string form. The
grammar/semantics are different: block form is a control-flow
construct; string form is a call that compiles and runs a string
at runtime.

**Does Chalk support the feature?** No — Chalk has no `eval`
rule at all. The memory file explicitly says "try/catch, not
eval blocks" is the Chalk convention, and Chalk uses
`TryCatchStatement` (grammar has it). String form is excluded
entirely because Chalk is a compile-time static compiler.

**How Chalk handles it today:** `eval` would parse as
`QualifiedIdentifier` (keyword fallthrough to identifier). It
would then be a bareword function call `eval ...` which is a
semantic error in Chalk's subset but not a syntactic one.

**Recommended disposition:** **exclude** (current state; document
it). Both forms are already excluded:
- Block form is replaced by `try/catch` in Chalk.
- String form cannot be statically compiled.

- **Rule-explosion test:** N/A.
- **Layer-violation test:** The lookahead-based split is itself
  token-shape (one char), so if Chalk wanted to support both,
  grammar could express it with two alternatives. But Chalk
  doesn't want to support either. Exclude.

---

### Point 14: `do { BLOCK }` vs `do "FILE"` vs `do SUB(...)`

**Perl example:**
```perl
do { $x; $y }          # block: sequenced expressions, returns last
do "config.pl"         # file: read, compile, execute
do &foo()              # sub call: calls foo() (deprecated but legal)
```

**toke.c citation:** `toke.c:7184-7211` — `yyl_do`:
```c
s = skipspace(s);
if (*s == '{')
    PRETERMBLOCK(KW_DO);          /* block do */
if (*s != '\'') {
    /* possibly a bareword for do FILE or do &SUB */
    char *d = scan_word(s, PL_tokenbuf + 1, ...);
    if (len && ... && !keyword(...)) {
        if (*d == '(') {
            force_ident_maybe_lex('&');  /* do &sub() */
        }
    }
}
OPERATOR(KW_DO);
```
Three modes: block, file, sub-call — disambiguated by `{` vs
bareword vs quote.

**Does Chalk support the feature?** Partially. Chalk's grammar has
no `DoStatement` / `DoExpression` rule. `do` is not in Chalk's
keyword list for grammar rules. It would parse as
`QualifiedIdentifier`, producing a call-expression or bareword.

**Recommended disposition:** **exclude** for file and sub-call
forms; add-and-restrict **grammar** for block form if desired.
Block `do { ... }` is a useful feature (an immediately-invoked
anonymous block returning the last value). File-do is
deprecated-equivalent to `require`. Sub-call `do &sub(...)` is a
deprecated alias for `&sub(...)`.

- **Rule-explosion test:** No for block form (one terminal + one
  rule).
- **Layer-violation test:** No for block form.

For block form: new rule `DoBlockExpression ::= /do\b/ _ Block`
added under Atom/Expression. The keyword/identifier
disambiguation follows the Class 2 pattern.

---

### Point 15: `<...>` readline vs less-than

**Perl example:**
```perl
my $line = <FH>;           # readline
my $line = <>;             # diamond (readline from @ARGV)
my @files = <*.pl>;        # glob
my $cmp = $a < $b;         # less-than
while (<STDIN>) { }        # readline
1 < 2;                     # less-than
```

**toke.c citation:** `toke.c:6844-6857` — `yyl_leftpointy`:
```c
if (PL_expect != XOPERATOR) {
    if (s[1] != '<' && !memchr(s,'>', PL_bufend - s))
        check_uni();
    if (s[1] == '<' && s[2] != '>')
        s = scan_heredoc(s);
    else
        s = scan_inputsymbol(s);
    PL_expect = XOPERATOR;
    TOKEN(sublex_start());
}
/* else: less-than operator */
```
This is *exactly* the same `PL_expect`-driven pattern as
Classes 4 and 6 — at an XTERM position, `<` begins readline (or
heredoc for `<<EOF`); at an XOPERATOR position, `<` is binary
less-than.

Additionally, inside `scan_inputsymbol` (`toke.c:11417+`), the
content `<TOKEN>` is further disambiguated:

- `<$fh>` (scalar variable) → treat `$fh` as filehandle (readline).
- `<FH>` (bareword) → treat as filehandle (readline).
- `<*.c>` (non-identifier contents) → treat as glob pattern.
- `<>` (empty) → diamond operator, same as `<ARGV>`.
- `<<>>` (triple angle) → no-magic readline.

The discrimination between readline and glob is **shape-based**:
`if (d - PL_tokenbuf != len) { ival = OP_GLOB; }` (line 11476)
says "if what we read looks like more than an identifier, it's
a glob pattern."

**Nature of the ambiguity:** Two layers:
1. `<` as operator vs as start of `<...>` construct
   — resolved by XTERM/XOPERATOR (same as Class 4/6 pattern).
2. `<CONTENTS>` as readline vs glob — resolved by contents
   shape (identifier-only → readline; other → glob).

**Does Chalk support the feature?** Not the `<...>` readline/
diamond/glob syntax. Grammar has no `ReadlineExpression` or
`DiamondOperator` rule. `<FH>` would fail to parse as an atom.
Binary `<` is in `BinaryOp`.

**Recommended disposition:** Layer 1 is **not-yet-supported**.
If added, same mechanism as Class 4 (slash): the grammar admits
both interpretations; a semiring (Precedence or TypeInference)
resolves by position. Layer 2 (readline vs glob) would then be
**grammar**: content-shape-based alternatives inside the
`<...>` rule.

- **Rule-explosion test for layer 1:** No (one rule, one
  terminal). **For layer 2:** No (two alternatives based on
  contents).
- **Layer-violation test for layer 1:** Yes — position-based,
  same as Classes 4/6, needs semiring.

Recommend adding a new class (**Class 10: Readline vs less-than**)
to the admitted-ambiguity list if the `<...>` feature is
supported; its resolver would be the same position-based
mechanism used by Classes 4/6. Layer 2 (readline vs glob) is
grammar-encodable and needs no new class.

---

### Point 16: `<<EOF` heredoc vs left-shift

**Perl example:**
```perl
my $s = <<EOF;
text
EOF
my $n = 1 << 2;    # left-shift
print <<~EOF;      # indented heredoc
    text
    EOF
my @s = (<<A, <<B);
    block A
    A
    block B
    B
```

**toke.c citation:** `toke.c:6851-6852` in `yyl_leftpointy`:
```c
if (s[1] == '<' && s[2] != '>')
    s = scan_heredoc(s);
```
`<<` at XTERM position with the third char not `>` is a heredoc
(`<<EOF`, `<<'EOF'`, `<<"EOF"`, `<<~EOF`). At XOPERATOR position,
`<<` is left-shift. `<<>>` (three angles) is special — the no-magic
readline, not a heredoc.

Heredoc scanning (`S_scan_heredoc`, `toke.c:10963-11416`) is
itself a **multi-line** disambiguation: the heredoc *body*
appears after the next newline, not inline where `<<EOF`
appeared. The tokenizer extracts the delimiter (`EOF`), then
remembers to scan the body from the next line. Multiple
heredocs in one line (`my @x = (<<A, <<B);`) stack in the order
they were seen.

**Nature of the ambiguity:**
1. `<<` shape at XTERM vs XOPERATOR — positional, same as the
   `<` case (Point 15).
2. Within heredoc form: the body-starts-on-next-line semantics
   creates a **non-local token stream** disambiguation —
   `<<EOF` at position N affects what's consumed at some
   position M > N (after the next newline). This is beyond
   Earley's local chart.

**Does Chalk support the feature?** No. Grammar has no heredoc
rule. `StringLiteral` covers `'...'`, `"..."`, `q{...}`,
`qq{...}`, backticks, but not heredocs.

**Recommended disposition:** **not-yet-supported**; if added,
**restrict** to single-line forms or handle via pre-lex
rewriting.

The non-local token stream issue is fundamentally a tokenizer
concern — BNF grammars describe token sequences, and heredocs
intentionally break locality by stashing content at a remote
position. Options:
1. Pre-lex transform — rewrite heredocs into inline quoted
   strings before parsing (this is what some tools do).
2. Grammar pretends the body is wherever the `<<TAG` appears,
   with a specialized terminal regex that matches `<<TAG\n...body...TAG`
   — but this requires a non-anchored regex spanning multiple
   lines.
3. Exclude.

- **Rule-explosion test:** No (one rule).
- **Layer-violation test:** Yes, severely — the semantics
  require either tokenizer state (Perl's approach) or pre-lex
  rewriting. Neither is a clean BNF fit.

Recommend excluding heredocs from Chalk's Perl subset;
document explicitly. This is a significant Perl-feature
restriction worth its own entry.

---

### Point 17: Quote-like operator delimiter choice and nesting

**Perl example:**
```perl
q/hello/               # / delimiter
q(hello)               # () with nesting: q(a (b) c) is literal
q{hello}               # {} with nesting
q!hello!               # ! delimiter (any non-alnum)
qw/a b c/              # list of words
qr(pattern)            # compiled regex
s{pat}{rep}            # paired delimiters
m|pat|                 # alternative regex delimiter
tr[abc][xyz]           # transliteration

# nested bracket pairs track:
q(a (b) c)             # "a (b) c" — parens balance
q[a [b] c]             # "a [b] c" — brackets balance
```

**toke.c citation:** `toke.c:11573-11929` — `Perl_scan_str` and
bracket-pair handling. The tokenizer accepts essentially any
non-alnum character (and non-ASCII graphemes) as a delimiter for
`q`-like operators.

```c
/* after skipping whitespace, the next character is the delimiter */
if (! UTF || UTF8_IS_INVARIANT(*s)) {
    open_delim_code = (U8) *s;
    ...
}
```

Bracket-pair delimiters (`()`, `[]`, `{}`, `<>`, and various
Unicode brackets) enable nesting. Non-bracket delimiters don't
nest.

**Nature of the ambiguity:** Not strictly an ambiguity — once
the tokenizer sees `q`/`qq`/`qw`/`qr`/`m`/`s`/`tr`/`y`, the next
non-space char is the delimiter. But this is a *parsing
mechanism* with a very broad shape: `q X ... X` where X is
any grapheme and `...` can contain `X` via escaping or via
bracket balancing. BNF cannot express "arbitrary delimiter that
must match later" directly.

Chalk's grammar currently has:
```bnf
StringLiteral ::= /'(?:[^'\\]|\\.)*'/
    | /"(?:[^"\\]|\\.)*"/
    | /q\s*\{(?:[^}\\]|\\.)*\}/
    | /q\s*\[(?:[^\]\\]|\\.)*\]/
    | /qq\s*\{(?:[^}\\]|\\.)*\}/
    | /qq\s*\[(?:[^\]\\]|\\.)*\]/
    | /`(?:[^`\\]|\\.)*`/ ;
RegexLiteral ::= /\/(?:[^\/\\\n]|\\.)*\/[msixpodualngcer]*/
    | /m\s*\/(?:[^\/\\]|\\.)*\/[msixpodualngcer]*/
    | /qr\s*\/(?:[^\/\\]|\\.)*\/[msixpodualngcer]*/
    | /s\s*\/(?:[^\/\\]|\\.)*\/(?:[^\/\\]|\\.)*\/[msixpodualngcer]*/
    | /s\s*\{(?:[^}\\]|\\.)*\}\s*\{(?:[^}\\]|\\.)*\}[msixpodualngcer]*/
    | /m\s*\{(?:[^}\\]|\\.)*\}[msixpodualngcer]*/ ;
QwLiteral ::= /qw\s*\([^)]*\)/ ;
```

The grammar supports `q{}`, `q[]`, `qq{}`, `qq[]`, `m//`, `m{}`,
`qr//`, `s///`, `s{}{}`, `qw()`. It does **not** support:
- `q()`, `q<>`, or any non-`{}/[]` delimiter for `q`.
- `qq()`, `qq//`, `qq<>`.
- `qw{}`, `qw[]`, `qw<>`, `qw//`.
- `qr{}`, `qr[]`, `qr()`.
- Nested brackets inside `q{...}` — `q{a{b}c}` would fail
  because the regex `[^}\\]` doesn't handle nesting.

**Does Chalk support the feature?** Partially — only a subset of
delimiters. The grammar doesn't support bracket nesting inside
bracket-delimited forms, nor arbitrary user-chosen delimiters.

**Recommended disposition:** **restrict** (current state, but
broaden if needed). Supporting the full Perl set requires either:
1. Many more alternatives in the grammar (one per delimiter
   shape) — bounded but large (5 base ops × ~10 delimiter
   shapes × with-nesting-variants).
2. A tokenizer pre-pass that recognizes the quote operators and
   emits a single STRING token — the approach Perl uses.

For bracket-nesting specifically, Perl 5's `scan_str` tracks
nesting depth at tokenizer time. Chalk's `\G`-anchored terminal
regexes **cannot express balanced bracket matching** (this is
famously the thing regex can't do). Fully matching Perl requires
a scan-time stateful recognizer.

- **Rule-explosion test:** Moderate — 5 ops × 10 delimiter shapes
  = ~50 alternatives for non-nesting. Nesting is unbounded, so
  regex-only cannot cover it.
- **Layer-violation test:** For nesting, yes — can't be expressed
  in BNF terminals. Would need a custom tokenizer layer.

Recommend either (a) accept the current restricted set and
document the restriction explicitly, or (b) add a custom
pre-tokenizer pass for quote-like operators. This is an
**important unexplored architectural question** — does Chalk
commit to handling only brace- and bracket-delimited forms, or
does it need a quote-op pre-lex?

Flag for follow-up. I would also add this as its own
architectural concern — it's not strictly "ambiguity" but
"delimiter extensibility" is a structural gap.

---

### Point 18: POD segments vs code

**Perl example:**
```perl
my $x = 1;

=head1 NAME

pod text here

=cut

my $y = 2;    # back to code
```

**toke.c citation:** `toke.c:9399-9427`:
```c
if (PL_expect == XSTATE
    && isALPHA(tmp)
    && (s == PL_linestart+1 || s[-2] == '\n') )
{
    if (PL_in_eval && ...) {
        /* skip to =cut */
    }
    s = PL_bufend;
    PL_parser->in_pod = 1;
    goto retry;
}
```
POD segments start with `=WORD` at the beginning of a line in
XSTATE context. They extend until `=cut` at the beginning of a
line. The `=` character is ambiguous:
- At XOPERATOR: `=`, `==`, `=~`, `=>` — various operators.
- At XSTATE at start-of-line, followed by a letter: POD start.
- At XSTATE otherwise: syntax error (stray `=`).

Later handling in `yyl_try` (`toke.c:7366-7380`) also consumes
POD lines when `PL_parser->in_pod` is set:
```c
if (PL_parser->in_pod) {
    if (memBEGINPs(s, ..., "=cut") ...) {
        PL_parser->in_pod = 0;
    }
} while (PL_parser->in_pod);
```

**Nature of the ambiguity:** `=head1` at start-of-line is POD;
elsewhere, `=` is an operator.

**Does Chalk support the feature?** Unclear. The grammar's
whitespace rule is:
```bnf
_ ::= /(?:\s|#[^\n]*)*/ ;
```
which only strips whitespace and `#` comments. There is no POD
handling. If a Perl file with POD is fed to Chalk, the `=head1`
would be lexed as `=` operator followed by `head1` — a parse
error.

Given the memory file says "Chalk recognizes XS.pm (5821 lines)",
and real Perl modules often contain POD, Chalk almost certainly
needs POD-stripping. Either via a pre-lex pass or by extending
the `_` whitespace rule.

**Recommended disposition:** **grammar** (extend the `_` rule) or
**pre-lex transform**. POD is entirely self-delimiting, so a
grammar-level rule that matches a POD block can strip it:
```bnf
_ ::= /(?:\s|#[^\n]*|^=[a-zA-Z]\w*[\s\S]*?^=cut\s*$)*/ ;
```
but regex multi-line matching requires `/m` flags, and Chalk's
`\G`-anchored terminals would need to handle start-of-line
constraints.

- **Rule-explosion test:** No (zero new rules if absorbed into `_`).
- **Layer-violation test:** No — POD is textually self-delimiting,
  no semantic context needed.

Flag for investigation. Ask perigrin whether Chalk currently
handles POD, and how. This is a high-priority question because
real-world Perl modules almost always contain POD.

---

### Point 19: `__END__` / `__DATA__` as file terminators

**Perl example:**
```perl
print "code";

__END__
anything down here is ignored (or accessible via DATA if __DATA__)
```

**toke.c citation:** `toke.c:7967-7971`:
```c
case KEY___DATA__:
case KEY___END__:
    if (PL_rsfp && (!PL_in_eval || PL_tokenbuf[2] == 'D'))
        yyl_data_handle(aTHX);
    return yyl_fake_eof(aTHX_ LEX_FAKE_EOF, FALSE, s);
```
These pseudo-keywords cause the tokenizer to emit EOF mid-file,
effectively truncating the source. `__DATA__` additionally sets
up the `DATA` filehandle for runtime access.

**Nature of the ambiguity:** Mild — `__END__` and `__DATA__`
could be identifiers in some hypothetical grammar. Perl reserves
them unconditionally.

**Does Chalk support the feature?** No grammar rule for them;
they would parse as `QualifiedIdentifier` (matching the
`[a-zA-Z_]\w*` regex). They would then be treated as function
calls, which would fail semantically.

**Recommended disposition:** **grammar** (extend) or **pre-lex**.
Easiest: add `__END__` and `__DATA__` as keywords and have the
preprocessor (or the `_` whitespace rule) consume everything
from there to end-of-file.

- **Rule-explosion test:** No (one pattern).
- **Layer-violation test:** No.

Bounded; flag as not-yet-supported, grammar-encodable.

---

### Point 20: Formats (`format NAME = ... .`)

**Perl example:**
```perl
format STDOUT =
@<<<<<<<<<<<<<<<<<<
$name
.

write;
```

**toke.c citation:** `toke.c:9430-9443` (dispatches `yyl_leftcurly`
with formbrack), `toke.c:12624-12770` (`S_scan_formline`). Formats
use their own multi-line parsing mode (form_lex_state); the body
ends at a line containing only `.`.

**Does Chalk support the feature?** No. The grammar has no
`format` rule. This would parse as `QualifiedIdentifier` followed
by garbage.

**Recommended disposition:** **exclude**. Formats are a legacy
feature rarely used in modern code; excluding them is a
defensible subset restriction.

Document explicitly alongside the other excluded features.

---

### Point 21: `FUNC` paren form vs `LSTOP` no-paren form (binding)

**Perl example:**
```perl
print(1, 2) + 3        # FUNC: (print(1,2)) + 3
print 1, 2 + 3         # LSTOP: print(1, 2+3)
```

**toke.c citation:** `toke.c:2129-2153` — `S_lop`:
```c
if (*s == '(')
    return REPORT(FUNC);
s = skipspace(s);
if (*s == '(')
    return REPORT(FUNC);
else {
    ...
    return REPORT(t);    /* LSTOP */
}
```
Lookahead on `(` determines whether the call is `FUNC` (function
form with tight binding like a unary op) or `LSTOP` (list
operator form with very loose right binding).

**Nature of the ambiguity:** `print 1, 2 + 3` binds `+` tighter
than `,`, giving `print(1, 2+3)`. But `print (1, 2) + 3` — the
space makes it `(print(1,2)) + 3` — parens-immediately-after
changes precedence. This is a notorious Perl gotcha.

**Does Chalk support the feature?** The grammar has both
forms:
```bnf
CallExpression ::= QualifiedIdentifier _ /\(/ _ ExpressionList? _ /\)/
    | QualifiedIdentifier WS ExpressionList
```
The first (paren form) and second (space form) are distinct
alternatives. The Precedence semiring then handles the binding.

**How Chalk handles it today:** The `_` between identifier and
`(` in the first alternative allows optional whitespace — so
`print(1)` and `print (1)` match the same production. **This
erases the Perl distinction.** Chalk treats both as `FUNC`-style.

This is actually a **silent behavioral difference from Perl** —
if a Chalk-compiled program uses `print (1,2) + 3`, Chalk will
bind it as `print((1,2)) + 3` = same as `print(1,2) + 3` =
`print(1,2,3)` (if the list flattens). Perl binds as
`(print(1,2)) + 3`. Different results.

**Recommended disposition:** **document as a restriction** — Chalk
treats `ident (...)` and `ident(...)` identically, unlike Perl.
This is arguably an improvement (no gotcha), but it's a semantic
divergence users should know about. If Perl bug-compatibility is
required, the `_` in the grammar would need to change to strict
no-space or `WS`-distinguishes-the-form.

- **Rule-explosion test:** No (already in grammar).
- **Layer-violation test:** Not really — it's a lexical
  whitespace distinction, could be encoded in grammar.

Flag for investigation. This is a **previously-undocumented
semantic divergence** that the maintainer may want to either
accept as a feature or fix for compatibility.

---

### Point 22: `{` in interpolated string — subscript vs literal

**Perl example:**
```perl
"value: $h{key}"       # subscript on hash
"text {literal}"       # literal braces in string
"text ${x}more"        # ${...} forces scalar interpolation
"text $x{k}more"       # subscript: $h{k} followed by 'more'
"$x {not subscript}"   # space after $x breaks subscript, literal {
```

**toke.c citation:** `toke.c:4493-4770` — `S_intuit_more` is the
big heuristic for "is what follows `$var` a subscript or plain
text?" It uses position-weighted heuristics (with explicit
comments about how ugly and unreliable this is — see the kwh
comment at line 4499).

`scan_ident` (line 10502+) calls `intuit_more` when it finds
`$x{...}` / `$x[...]` in an interpolated context. The result
decides whether `{...}` is captured as a subscript or left as
literal text.

**Nature of the ambiguity:** Inside double-quoted strings,
`$foo{bar}` is a hash subscript, but `$foo {bar}` (with space) is
`$foo` followed by literal ` {bar}`. The rule isn't purely
whitespace — `intuit_more` also considers whether the contents
look like an expression (e.g. `$x[1]` is always a subscript,
while `$x[abc def]` might be literal if `abc def` doesn't look
like an index).

**Does Chalk support the feature?** Chalk's grammar has limited
string interpolation:
```bnf
StringLiteral ::= ...
    | /"(?:[^"\\]|\\.)*"/    # double-quoted, anything but " and \
```
The regex doesn't parse the **contents** of `"..."` — it's one
atomic terminal. Chalk doesn't analyze interpolated-string
internals at grammar level. Whatever interpolation semantics
Chalk implements must happen in post-parse processing.

**Recommended disposition:** **restrict** or **post-parse-semantics**.
If Chalk wants to faithfully emit code that reproduces Perl's
interpolation behavior, it needs to either:
1. Sublex strings the way Perl does (full re-entry into the
   lexer), which recreates `intuit_more` issues.
2. Implement a simpler, documented interpolation model (e.g.
   "`$name`, `@name`, `${expr}`, `@{expr}` only; no subscripts
   in strings"). Several modern Perl projects have chosen this.

- **Rule-explosion test:** Unclear — depends on whether string
  contents become grammar-parsed or remain opaque.
- **Layer-violation test:** The `intuit_more` weights are a
  statistical heuristic — reproducing them is a layer violation
  by any metric.

Recommend restriction (simpler interpolation model) and explicit
documentation. Flag as a significant architectural question.

---

### Point 23: `$#var` array-last-index vs `$#` array-slice-prefix

**Perl example:**
```perl
my $last = $#arr;          # last index of @arr
my @a = $#{$ref};          # last index of dereffed array
my @slice = @arr[0..$#arr] # in list context, array slice
```

**toke.c citation:** `toke.c:5360-5373` in `yyl_dollar`:
```c
if (s[1] == '#'
    && (isIDFIRST_lazy_if_safe(s+2, ...) || memCHRs("{$:+-@", s[2])))
{
    PL_tokenbuf[0] = '@';
    s = scan_ident(s + 1, PL_tokenbuf + 1, ...);
    ...
    TOKEN(DOLSHARP);
}
```
`$#` followed by an identifier or one of `{$:+-@` is
`DOLSHARP` (array last-index). Otherwise, `$#` might be a
punctuation variable (`$#` itself, old "output format" special).

**Nature of the ambiguity:** `$#` alone vs `$#name` — the former
is a deprecated special variable, the latter is array-last-index.
In most modern code this is unambiguous.

**Does Chalk support the feature?** Yes, partially. Grammar:
```bnf
ScalarVariable ::= /\$[a-zA-Z_]\w*/
    | /\$\d+/
    | /\$\$[a-zA-Z_]\w*/
    | /\$#[a-zA-Z_]\w*/    # <-- $#name supported
    | /\$#\$[a-zA-Z_]\w*/  # <-- $#$ref supported
```
Two last-index forms are captured. Not covered: `$#` alone,
`$#{...}` (array-ref last-index via dereference), `$#+` and
similar punctuation variants.

**Recommended disposition:** **grammar** (already mostly done).
`$#` alone is deprecated and can be excluded. `$#{EXPR}` (array-ref
last index via explicit deref) could be added if Chalk supports
complex deref. This is **already grammar-encoded**; minor gaps
are bounded.

- **Rule-explosion test:** No.
- **Layer-violation test:** No.

Flag: confirm that `$#{...}` and `$#arr[0..$#arr]` in list
context round-trip correctly through Chalk.

---

### Point 24: `$$` process-ID vs scalar deref vs string interpolation

**Perl example:**
```perl
print $$;              # $$ alone — process ID (special variable)
print $$ref;           # scalar deref of $ref
print "$$";            # PID interpolated
print "$$ref";         # PID + literal "ref" (NOT deref in string)
my $deref = ${$ref};   # explicit scalar deref
```

**toke.c citation:** `yyl_dollar` + `scan_ident` interaction. The
`$$` case is subtle:

- `$$` alone (followed by non-identifier, non-`{`, non-`$`) is
  the special variable (PID).
- `$$name` (followed by identifier) is scalar deref: `${$name}`.
- In strings, `"$$"` interpolates PID (no deref inside strings
  without braces).
- In strings, `"$$ref"` interpolates PID then literal `ref` — NOT
  deref.

The discrimination happens in `scan_ident` (line 10407):
```c
if (*s == '$' && s[1]
    && (isIDFIRST_lazy_if_safe(s+1, ...)
        || isDIGIT_A(s[1]) || s[1] == '$' || s[1] == '{'
        || memBEGINs(s+1, ..., "::")))
{
    /* Dereferencing a value in a scalar variable. */
    return s;
}
```

**Does Chalk support the feature?** Partially. Grammar has:
```bnf
ScalarVariable ::= /\$[a-zA-Z_]\w*/
    | /\$\d+/
    | /\$\$[a-zA-Z_]\w*/     # <-- $$name = scalar deref
    | ...
```
`$$name` is supported as scalar deref. `$$` alone is not in the
grammar (no special variables of this form). `$$` in strings
isn't resolved (strings are opaque terminals).

**Recommended disposition:** **restrict** (current state).
Excluding `$$` alone is defensible — it's a special variable and
Chalk's subset generally excludes those. String interpolation
semantics are a separate concern (Point 22).

- **Rule-explosion test:** No.
- **Layer-violation test:** No.

No change needed; document that Chalk's `$$NAME` means scalar
deref only.

---

### Point 25: `@arr[...]` vs `@hash{...}` slices

**Perl example:**
```perl
@arr                   # array access
@arr[0,1]              # array slice
@arr{'a','b'}          # hash slice (confusingly, @-sigil for HASH slice)
@$ref                  # array deref
@{$ref}                # array deref (brace form)
print @arr             # list op arg
```

**toke.c citation:** `toke.c:6701-6730` `yyl_snail`:
```c
if (*s == '{')
    PL_tokenbuf[0] = '%';    /* @hash{...} is HASH slice */
/* Warn about @ where they meant $. */
if (*s == '[' || *s == '{')
    S_check_scalar_slice(s);
```
The sigil changes from `@` to `%` (internally) when followed by
`{`, to reflect that `@h{k1,k2}` is a hash slice despite the `@`
sigil. This is a user-facing ambiguity: the `@` says "list
context" but the `{}` says "hash lookup."

**Nature of the ambiguity:** `@var[...]` vs `@var{...}` — same
sigil, different containers via the bracket.

**Does Chalk support the feature?** Grammar:
```bnf
ArrayVariable ::= /@[a-zA-Z_]\w*/
    | /@\$[a-zA-Z_]\w*/ ;
```
Bare `@name` and `@$ref`. No explicit rule for slices — `@arr[0,1]`
would parse as `ArrayVariable` + `[0,1]` subscript (`Subscript`
rule at §16). `@hash{k1,k2}` would parse as `ArrayVariable`
(matching `@hash`) + `{k1,k2}` subscript — but the second
`Subscript` alt requires `Expression _ /\{/ _ Expression _ /\}/`,
not `ExpressionList`. That's a grammar gap: array/hash slices
via `@arr[1,2]` don't work because `Subscript` admits only one
`Expression` inside the brackets, not a list.

**Recommended disposition:** **grammar** — extend `Subscript` to
admit `ExpressionList` inside `[...]` and `{...}`.

- **Rule-explosion test:** No (modify one rule, add one alt).
- **Layer-violation test:** No.

Flag as a grammar gap; bounded fix.

---

### Point 26: `%var` hash vs `%` modulo operator vs `%h{k}` slice

**Perl example:**
```perl
my %h = (a => 1);
my $x = 5 % 3;             # modulo
print %h;                  # all key/value pairs
print %h{'a','b'};          # key/value slice (NEW in 5.20+)
```

**toke.c citation:** `toke.c:6071-6101` `yyl_percent`:
```c
if (PL_expect == XOPERATOR) {
    /* binary %: modulo */
    Mop(OP_MODULO);
}
/* else: hash sigil */
PL_tokenbuf[0] = '%';
s = scan_ident(s, PL_tokenbuf + 1, ...);
```
`%` at XOPERATOR is modulo; at XTERM is hash sigil.

Additionally, `%hash{...}` is the key/value slice (introduced 5.20):
```perl
%hash{'a','b'}   # ('a' => 1, 'b' => 2)
```
This is a new form that the grammar may or may not handle.

**Nature of the ambiguity:** Position-based (same as Class 4/6).

**Does Chalk support the feature?** Grammar:
```bnf
HashVariable ::= /%[a-zA-Z_]\w*/
    | /%\$[a-zA-Z_]\w*/ ;
BinaryOp ::= ... | /[*\/%]/ | ... ;
```
`%name` and binary `%` are both in the grammar. Same position
ambiguity as Class 4. Same mechanism: Precedence semiring
decides. **Not yet documented but already admitted.**

Key/value slice (`%h{...}`) is not explicitly in the grammar —
similar issue to `@hash{...}` (Point 25).

**Recommended disposition:** This ambiguity is a **subcase of
Class 4's pattern** (position-based operator-vs-sigil). Add a
note to Class 4 or document as **Class 10** alongside other
sigil-vs-operator cases.

The specific `%foo` ambiguity is exactly `/pattern/` vs `$a /
$b` with different sigils/operators. Chalk's grammar + Precedence
semiring should already handle it, but **no test confirms this**.
Flag for test-coverage audit.

---

### Point 27: `?PATTERN?` one-time match

**Perl example:**
```perl
while (<>) {
    print if ?start?;   # matches pattern exactly once per reset
}
```

**toke.c citation:** `toke.c:10730-10750` in `scan_pat`:
```c
if (PL_multi_open == '?') {
    pm->op_pmflags |= PMf_ONCE;
    ...
}
```
Triggered via the per-character dispatch for `?` at XTERM
context. Note: **removed in recent Perl; deprecated and causes
fatal error in 5.22+** (`m?PAT?` without explicit `m` is a
syntax error). With explicit `m?PAT?` it still works.

**Does Chalk support the feature?** No; `?` is only in
`TernaryExpression` and `AssignOp` patterns. `?pat?` as bare
regex is not admitted.

**Recommended disposition:** **exclude**. Deprecated in Perl,
niche feature, exclusion is principled.

---

### Point 28: Attribute grammar extensibility (`:attr(args)`)

**Perl example:**
```perl
sub foo :method :lvalue :prototype($$) { ... }
field $x :param = 0;
field $y :param(name) :reader;
method bar :signature($x, $y) { ... }   # hypothetical
```

**toke.c citation:** `toke.c:6134-6253` `yyl_colon`:
```c
case XATTRBLOCK:
    PL_expect = XBLOCK;
    goto grabattrs;
...
grabattrs:
    while (isIDFIRST_lazy_if_safe(s, ...)) {
        ...
        if (*d == '(') {
            d = scan_str(d, TRUE, TRUE, FALSE, NULL);
            ...
        }
        ...
    }
```
Attributes consist of `:name` or `:name(args)`. The `args` are
parsed via `scan_str` as a parenthesized string (arbitrary
contents, including balanced parens). User-defined attribute
handlers can consume arbitrary attribute syntax via
`Attribute::Handlers` or the `MODIFY_CODE_ATTRIBUTES` hook. This
means attribute *semantics* are extensible, but the *syntax*
(`: IDENT ( CHARS )`) is fixed.

**Nature of the ambiguity:** None within `:name(args)` itself —
it's syntactically regular. But the colon is **highly
overloaded**:
- Inside attribute grammar: list separator (`: attr1 : attr2`).
- Inside ternary: `?:` colon.
- Inside labels: `LABEL: statement`.
- Inside attribute colons: sub/method/field declaration.
- Inside signatures: not used (reserved).
- Inside hash slicing access: not directly.
- Inside package names: `::` (double colon).

The `yyl_colon` dispatch uses `PL_expect` and `PL_in_my` state
to discriminate. At XATTRBLOCK/XATTRTERM, it's attribute start.
At XOPERATOR with `PL_in_my` set and specific conditions, it's
attribute. Otherwise it's a non-attribute colon (ternary or error).

**Does Chalk support the feature?** Grammar:
```bnf
Attribute ::= /:/ _ QualifiedIdentifier
    | /:/ _ QualifiedIdentifier _ /\(/ _ QualifiedIdentifier _ /\)/ ;
```
Chalk supports `:name` and `:name(arg)` where `arg` is a
single `QualifiedIdentifier`. It does **not** support:
- `:name(arbitrary text)` — e.g. `:prototype($$)`, where `$$` is
  not a QualifiedIdentifier.
- `:name(expr)` where expr contains commas, braces, etc.

This is a **significant restriction**. Real modules use
`:prototype($;@)` etc.; Chalk wouldn't parse these.

**Recommended disposition:** **restrict** (current) or **grammar**
(extend to arbitrary parenthesized contents).

To extend: change `Attribute` to
```bnf
Attribute ::= /:/ _ QualifiedIdentifier
    | /:/ _ QualifiedIdentifier _ AttributeArgString ;
AttributeArgString ::= /\((?:[^()\\]|\\.)*\)/ ;  # flat, no nesting
```
or with a custom balanced matcher if nesting is needed.

- **Rule-explosion test:** No.
- **Layer-violation test:** No.

Flag: confirm whether Chalk needs `:prototype(...)` support for
its target subset. If class-based Perl only, probably not
critical; if general Perl, essential.

---

### Point 29: Version strings (`v1.2.3`, `1.2.3`)

**Perl example:**
```perl
my $v = v1.2.3;           # version string (3-byte string)
my $v = 1.2.3;            # version string (implicit v)
use v5.42;                # version pragma
package Foo 1.0;          # package version
sub foo : v1 { }          # NOT a version — attribute
```

**toke.c citation:** `toke.c:9551-9586` (in `yyl_try` for the
`'v'` case), `toke.c:12601-12610` (scan_num vstring branch),
`toke.c:13317+` `Perl_scan_vstring`. The discrimination is
elaborate:

```c
case 'v':
    if (isDIGIT(s[1]) && PL_expect != XOPERATOR) {
        /* maybe vstring: v followed by digits */
        while (isDIGIT(*start) || *start == '_') start++;
        if (*start == '.' && isDIGIT(start[1])) {
            s = scan_num(s, &pl_yylval);
            TERM(THING);
        }
        /* multi-digit v-string without dot: need to check ambiguity */
        ...
    }
    if ((tok = yyl_keylookup(aTHX_ s, gv)) != YYL_RETRY)
        return tok;
```

Several heuristics decide whether `v1` is a version string or a
regular identifier `v1`:
- If followed by `.DIGIT`, it's vstring (`v1.2.3`).
- If at XSTATE and followed by `:`, it's a label.
- If followed by `::`, it's a package name.
- Otherwise, context-dependent.

Similarly, `1.2.3` (no leading `v`) is treated as a vstring in
`scan_num` when multiple dots appear.

**Nature of the ambiguity:** `v1` as bareword vs as vstring.
`1.2` as float vs `1.2.3` as vstring (requires third component).

**Does Chalk support the feature?** Grammar:
```bnf
Version ::= /v?[0-9]+(?:\.[0-9]+){2,}/ ;
ModuleName ::= QualifiedIdentifier
    | Version
    | QualifiedIdentifier WS Version ;
```
`Version` is used in `UseDeclaration` / `ModuleName` only. The
regex matches `v1.2.3` or `1.2.3` with at least two dots. **Good
coverage for use-statement context.**

But: `my $v = v1.2.3;` — would `Version` be predicted in
expression context? Looking at `Atom`, there's no `Version`
alternative. So vstring in expression context fails.

Also: `my $v = 1.2.3` (no `v`) — the float regex
`/[0-9](?:_?[0-9])*(?:\.[0-9](?:_?[0-9])*)?(?:[eE][+-]?[0-9]+)?/`
matches `1.2` greedily, stopping at the second `.`. So `1.2.3`
would parse as float `1.2` followed by `.3` — a syntax error.

**Recommended disposition:** **grammar** (extend `Atom` to admit
`Version`) or **restrict** (v-strings in expression context
unsupported; only use-declarations).

- **Rule-explosion test:** No.
- **Layer-violation test:** Technically the discrimination
  between `1.2.3` (vstring) and `1.2` followed by `.3` (error)
  is shape-based: three-dot sequences of digits are vstrings.
  Grammar can encode via regex ordering (try vstring first).

Flag: document that vstrings in expressions are
not-yet-supported.

---

### Point 30: Subroutine/block calls with `&` prefix

**Perl example:**
```perl
&foo;                  # call &foo with @_ reused from caller
&foo();                # call foo() with no args (no @_ reuse)
&foo(1, 2);            # call foo(1, 2)
&$coderef;             # dereference coderef and call
\&foo                  # reference to subroutine
&{$coderef};           # deref and call (brace form)
```

**toke.c citation:** `toke.c:6578-6630` `yyl_ampersand`:
```c
if (PL_expect == XPOSTDEREF)
    POSTDEREF(PERLY_AMPERSAND);

if (*s++ == '&') {
    /* && */ AOPERATOR(ANDAND);
}
...
PL_tokenbuf[0] = '&';
s = scan_ident(s - 1, PL_tokenbuf + 1, ...);
```
`&` is reference/sigil vs binary bitwise AND vs `&&`, plus
postderef `&*` in deref context.

**Does Chalk support the feature?** Grammar has binary `&`:
```bnf
BinaryOp ::= ... | /&(?!&)/ | ...
```
Also `&&`. But there is **no rule for `&foo` as subroutine
invocation via ampersand prefix, nor `\&foo` reference**. Those
would parse partly:
- `\&foo` — `/\\/` in UnaryExpression matches `\`, then `&foo`
  needs to parse as Expression. But `&foo` is not an Atom.
  Probably fails.
- `&foo` — `&` is only a BinaryOp in Chalk's grammar; at
  statement start, it has no admission.

**Recommended disposition:** **exclude** (current state).
Ampersand-prefix sub calls are legacy and rare in modern Perl.
Taking references to named subs via `\&foo` is more common and
might want **grammar** support (add `SubRef ::= /\\&/
QualifiedIdentifier` to Atom).

Flag: confirm Chalk's stance on `\&foo` refs. If supported
elsewhere via a different mechanism, fine; if not, minor grammar
extension.

---

### Point 31: `package NAME` block form vs statement form

**Perl example:**
```perl
package Foo;           # statement form: affects current package until next
package Foo { ... }    # block form: lexically scoped
package Foo VERSION;   # with version
package Foo VERSION { ... }   # all together
```

**toke.c citation:** `toke.c:8529-8540`:
```c
case KEY_package:
    s = force_word(s, BAREWORD, FALSE, TRUE);
    s = skipspace(s);
    s = force_version(s, FALSE);
    PREBLOCK(KW_PACKAGE);
```
`force_word` grabs the package name, optional version, then
`PREBLOCK` — the next `{` (if any) is parsed as a block; else
it's a statement-ending `;`.

**Does Chalk support the feature?** No explicit `PackageDeclaration`
rule in grammar. `package Foo;` would parse as `CallExpression
::= QualifiedIdentifier WS ExpressionList` then `;`. `package`
isn't in the keyword-rule-mapped keywords. So Chalk admits it as
a bareword-ish call, not as a package declaration. Semantically
this is wrong — `package Foo` in Chalk's IR wouldn't establish a
namespace boundary.

**Recommended disposition:** **grammar** (add `PackageDeclaration`)
if Chalk cares about legacy `package` syntax, or **exclude** if
Chalk's class-based model is the only supported form. Given
Chalk uses `class` blocks (and doesn't use `package` based on
the grammar), probably exclude.

Flag: confirm Chalk's stance on `package`.

---

### Point 32: Lexical `state`/`our`/`local` vs `my`

**Perl example:**
```perl
my $x;                 # lexical
our $x;                # package global, lexically aliased
state $x;              # persistent (keeps value across calls)
local $var;            # dynamic scoping (save/restore)
field $x :param;       # class field (5.42+)
```

**toke.c citation:** `toke.c:7226+` `yyl_my` handles `my`,
`state`, `our`. `local` is handled separately. `field` is new in
5.42. Grammar shares similar shape: DECLARATOR VAR, optionally
with attributes and initializer.

**Does Chalk support the feature?** Yes:
```bnf
VariableDeclaration ::= /(?:my|our|state|local|field)\b/ WS Variable AttributeList?
    | /(?:my|our|state|local|field)\b/ WS /\(/ _ VariableList _ /\)/ ;
```
All five are admitted. Good coverage.

No ambiguity worth discussing — this is straightforward
keyword-dispatch, already covered by Class 2.

---

### Point 33: Indirect method call via `->method` vs direct call

Covered by existing docs (Class 8: excluded indirect syntax).
`$obj->method` direct-method syntax is grammar-encoded (see
`MethodCall` in grammar). No new point.

---

## Summary table

| # | Name | Nature | Chalk status | Recommended disposition |
|---|---|---|---|---|
| 10 | `-X` file test vs unary minus | Shape-based: `-` + filetest letter + non-word | Not supported | grammar (if adding) |
| 11 | Prototype vs signature on `sub (` | Feature-flag-driven | Not supported (signatures-only) | exclude (prototypes) |
| 12 | User-sub prototype-driven parsing | Runtime symbol table | Not supported | exclude (same as class 8) |
| 13 | `eval` block vs string form | 1-char lookahead | Not supported (try/catch instead) | exclude |
| 14 | `do { }` vs `do "FILE"` vs `do &SUB(...)` | Lookahead shape | Not supported | grammar for block; exclude rest |
| 15 | `<...>` readline vs less-than | Position-based (XTERM/XOPERATOR) | Not supported | admit + semiring (same as Class 4) |
| 16 | `<<EOF` heredoc vs left-shift | Position + non-local body | Not supported | restrict/exclude |
| 17 | Quote-op delimiter extensibility | Arbitrary + nesting | Partial (limited delimiters) | restrict (document) or pre-lex |
| 18 | POD segments | Start-of-line `=word` | Unclear (likely gap) | grammar (extend `_`) — investigate |
| 19 | `__END__` / `__DATA__` | Pseudo-keyword truncates source | Not supported | grammar |
| 20 | Formats | Multi-line format-body state | Not supported | exclude |
| 21 | `FUNC` vs `LSTOP` whitespace distinction | Space before `(` changes binding | Erased (grammar treats as one) | document as restriction |
| 22 | `{` in interpolated string | Weighted heuristic (`intuit_more`) | Strings opaque (no interpolation analysis) | restrict interpolation model |
| 23 | `$#var` array-last-index | Sigil composition | Supported | grammar (document) |
| 24 | `$$` PID vs `$$name` deref | Context-dependent | `$$name` supported; PID `$$` excluded | restrict (current) |
| 25 | `@arr[...]` vs `@hash{...}` slices | Sigil + bracket discrimination | Partial (subscripts admit single expr only) | grammar (fix Subscript rule) |
| 26 | `%` modulo vs `%` hash-sigil | Position-based (same as Class 4) | Admitted; not documented | document as Class 4 subcase |
| 27 | `?pattern?` one-time match | Deprecated | Not supported | exclude |
| 28 | `:attr(args)` attribute argument syntax | Arbitrary parenthesized string | Partial (single identifier only) | grammar (extend if needed) |
| 29 | Version strings in expressions | Multi-dot digits | Supported in `use`; not in Atom | grammar (extend if needed) |
| 30 | `&foo` sub-call, `\&foo` ref | Sigil + name pattern | Not supported | exclude or grammar for `\&foo` |
| 31 | `package` statement/block form | Lookahead on `{` vs `;` | Not supported | grammar or exclude |

## Key findings

1. **Perl features Chalk silently rejects via grammar.** `-X`
   file tests, heredocs, formats, `?PAT?`, `&foo`, `package`,
   `__END__` — Chalk's grammar simply doesn't have rules for
   these, so source using them will fail to parse. This is
   **defensible exclusion for a subset**, but the exclusions are
   not currently documented. `docs/chalk-grammar-spec.md` §9
   (Known Limitations) should be audited for completeness.

2. **POD handling is unclear and high-priority.** Real-world
   `.pm` files almost always contain POD; the grammar's `_`
   whitespace rule does not strip POD; I could not find any
   pre-lex pass that does. If Chalk currently parses files with
   POD, something is stripping it that I didn't find. If it
   doesn't, Chalk cannot process most CPAN modules. This needs
   investigation before any further parsing work.

3. **Interpolated string internals are entirely opaque.** The
   grammar treats `"..."` as a single atomic terminal via regex.
   Chalk doesn't analyze `$foo{key}` inside strings at grammar
   time. This means whatever interpolation Chalk does must
   happen in post-parse processing. A deliberate architectural
   decision (avoids `intuit_more`-style heuristics) but should be
   documented.

4. **Quote-like operator delimiter support is narrow and silent.**
   Grammar admits `q{}`, `q[]`, `qq{}`, `qq[]`, `m//`, `m{}`,
   `qr//`, `s///`, `s{}{}`, `qw()`. Common forms like `q()`,
   `q//`, `q!!`, `qq()`, `qw//`, `qw{}`, `qw[]`, `qr{}`, `qr()`,
   `tr///`, `y///` are **not admitted**. Neither is bracket
   nesting inside `q{...}` (e.g. `q{a{b}c}`). This is a
   significant practical gap because modern Perl code uses
   diverse delimiters.

5. **Whitespace distinction in `FUNC` vs `LSTOP` is lost.**
   Chalk's grammar admits `print(1)` and `print (1)` as the
   same production (optional-whitespace `_` between identifier
   and `(`). Perl distinguishes them: `print (1,2) + 3` binds
   as `(print(1,2)) + 3`, not `print(1, 2+3)`. This is a silent
   semantic divergence. Either accept it as an improvement
   (Perl's behavior is a gotcha most documentation warns against)
   or fix with a grammar tweak.

6. **Array/hash slice grammar gap.** `Subscript` admits only one
   `Expression` inside `[...]` / `{...}`, not an `ExpressionList`.
   This means `@arr[0, 1, 2]` and `@hash{'a', 'b'}` probably
   don't parse. Either the grammar has a separate slice rule I
   missed, or this is a real gap.

7. **Two new ambiguity classes emerged.** Point 15 (`<...>`
   readline vs less-than) and Point 26 (`%` modulo vs hash
   sigil) are position-based ambiguities of the same flavor as
   Class 4 (slash vs regex). If either feature is supported, the
   existing Class 4 documentation should be generalized or a new
   class added. Currently `%` is admitted silently via the
   grammar (no documented class) — Chalk probably parses `%x + 1`
   and `5 % 3` correctly via Precedence semiring, but this is
   not tested or documented as an ambiguity.

8. **Attribute `args` limitation is practical.** Real attributes
   use arbitrary strings: `:prototype($$)`, `:param(name)` — Chalk
   admits only a single `QualifiedIdentifier`. This probably
   breaks `field $x :param(foo)` which is *exactly* the new
   5.38+ `feature class` syntax. Verify whether Chalk's test
   suite includes such cases.

9. **Prototype vs signature is a feature-flag problem.** Perl's
   `toke.c:5542` `is_sigsub = is_method || FEATURE_SIGNATURES_IS_ENABLED`
   means the same `(...)` after `sub NAME` means different things
   depending on a pragma. Chalk sidesteps this by assuming
   signatures-always, which is right for a modern subset but is
   a **divergence from Perl** worth documenting. Prototyped CPAN
   code using `($$)` prototype shape would fail to parse.

## Questions for the maintainer

1. **POD handling.** How does Chalk currently handle POD blocks
   in `.pm` files? Is there a pre-lex strip? Is it in the `_`
   whitespace rule somewhere I didn't find? Is it assumed the
   input is POD-stripped? This is the most practically important
   question.

2. **Quote-like operators.** Is the current restricted set
   (`q{}`, `q[]`, `qq{}`, `qq[]`, `m//`, `m{}`, `qr//`, `s///`,
   `s{}{}`, `qw()`) the intended scope, or is there an expansion
   planned? Does Chalk need to parse `qw/a b c/` or `qr{...}` or
   `tr///`? These appear in most Perl code.

3. **Heredocs.** Are these excluded by design, or just
   not-yet-supported? Real modules often use them for help text
   and SQL. A pre-lex rewrite is feasible; is it worth it?

4. **Interpolated string model.** What is Chalk's intended
   semantic for `"$foo[0]"` / `"$foo{k}"` / `"${foo}bar"`? Is
   string content parsed at all, or is it emitted as a
   `sprintf`-style template at code-gen time?

5. **`FUNC` vs `LSTOP` whitespace.** Is `print(1,2)+3` intended
   to bind the same as `print (1,2)+3`? If so, document as
   restriction; if not, grammar needs a tweak.

6. **Array/hash slices (`@arr[1,2]`).** Does `Subscript` need to
   admit `ExpressionList`? Are slices currently working via some
   other mechanism?

7. **Attribute argument syntax.** Does Chalk need `:param(name)`
   where `name` is a general expression, not just a
   `QualifiedIdentifier`? The 5.42 class syntax uses this.

8. **`\&foo` sub references.** Commonly used for passing sub
   refs; is this in Chalk's subset?

9. **`-X` file tests.** These are pervasive in CLI-style Perl.
   Is the plan to exclude them, or to add when Chalk reaches
   CLI-script support?

10. **Version strings in expressions.** `my $v = v1.2.3;` — needs
    grammar extension. Is this in scope?

11. **Two new proposed ambiguity classes (or extensions to Class
    4).** Should Point 15 (`<...>`) and Point 26 (`%`) become
    documented classes, or extensions of the existing Class 4
    writeup as generalized "position-based sigil/operator
    ambiguity"? The decision record's Class 4 is currently
    slash-specific.

12. **Silent behavioral divergences.** Chalk appears to differ
    from Perl in at least three places I identified (FUNC/LSTOP
    whitespace, prototype handling, interpolation internals).
    Should a document `docs/perl-divergences.md` or similar be
    created to track these?
