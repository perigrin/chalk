# Audit 1 — Grammar Findings

**Date:** 2026-04-25
**Companion to:** `docs/plans/2026-04-25-audit-1-grammar-brief.md`
**Status:** Findings, not remediation. Decisions belong to perigrin.

## Summary

- **Grammar gaps confirmed (Boolean rejects):** 2 from the seed list,
  4 additional discovered.
- **Pseudo-ambiguities discovered beyond the documented seven:** 4
  (the doc enumerates seven, not nine — see "ambiguity-classes.md
  drift" below).
- **Grammar over-permissiveness (admits malformed inputs):** 4 items.
- **Documented-class shape verification:** 7 of 7 classes admit the
  documented constructs under Boolean alone. Derivation counts could
  not be quantified — see "Methodology limitation" below.
- **Stale claims in adjacent docs:** 2 cross-document inconsistencies
  found (`-X` file tests, `ambiguity-classes.md` rule count).

Conformance harness baseline: `t/grammar-conformance.t` reports 121
of 148 `lib/` files parse successfully under the full filter stack
(per the brief). Audit 1 owns only the Boolean-rejected subset.

## Methodology limitation

The brief's acceptance criterion 3 asks for "the derivation count
recorded" per ambiguity class under Boolean alone. The Earley parser
collapses ambiguity through `Boolean::add()` which returns its left
operand when both sides are non-zero
(`lib/Chalk/Bootstrap/Semiring/Boolean.pm:64-66`). The chart is local
to `Earley::_run_parse` (`lib/Chalk/Bootstrap/Earley.pm:359`) and is
not exposed via reader. Counting `Boolean::add()` invocations via
monkey-patching produced numbers in the 60–280 range for any non-
trivial input — the count reflects Earley chart-cell sharing, not
class-specific derivation count. Even an empty class definition
produced 65 merges. Under the full filter stack, FilterComposite's
`tie_log` (`lib/Chalk/Bootstrap/Semiring/FilterComposite.pm:32`) is a
cleaner signal — recorded below per class.

Without per-rule chart inspection or a derivation enumerator, the
audit verifies admission qualitatively (does Boolean accept the
canonical input) and uses tie counts under the full stack as a proxy
for "how cleanly is this resolved." Both are below.

## Confirmed grammar gaps

Each gap was verified with a fresh Boolean-vs-full-stack probe.
Probe scripts were temporary in `/tmp/` and have been deleted.

### Gap 1: `->@[range]` postfix array slice

**Trigger:** `$ref->@[0..2]`, `$arr->@[1,2,3]`.

**Site count and locations:** Zero production sites currently. The
single former site at `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm:26`
was reverted in commit `cf14d82e` to `->@*` + `pop`.

**Boolean-rejects evidence:** Probe `S1.a` parses `my @x = $ref->@[0..2]; return;` —
both Boolean and full stack reject. `PostfixDeref`
(`docs/chalk-bootstrap.bnf:236-239`) admits four slice forms (`@*`,
`%*`, `$*`, `$#*`); none is `@[expr]`.

**Suggested remediation shape:**
```
PostfixDeref ::= ...existing four alts...
    | Expression _ /->/ _ /@/ _ /\[/ _ Expression _ /\]/ ;
```
Commit `36fce12b` added exactly this rule, then commit `cf14d82e`
reverted it because the TypeInference and Structural semirings then
filtered it incorrectly. Per the brief's seed data, the gap is
documented but not load-bearing.

**Side effects of the fix:** Adding the alternative may revive the
TypeInference/Structural filtering issue from `cf14d82e`. Owner of
that interaction is Audit 2 (semirings).

**Symmetric forms not yet present:** `->%[...]` (hash slice via
positional keys), `->@{...}` (hash slice via list keys). Probes
`S1.e` and `S1.f` confirm Boolean rejects both. These are out of
scope per the self-hosting scope audit
(`docs/plans/2026-04-24-self-hosting-scope-audit.md:457-460`) — zero
sites in `lib/`.

### Gap 2: anonymous-skip signature parameter `$,`

**Trigger:** `sub foo($, $real) { ... }`, `method m($, $x) { ... }`.

**Site count and locations:** One site in `lib/`:
`lib/Chalk/Bootstrap/IR/Optimizer.pm:10` (`sub collapse_phi($, $phi)`).

**Boolean-rejects evidence:** Probes S2.a–S2.f all reject under both
Boolean and full stack. `ScalarSignatureParam`
(`docs/chalk-bootstrap.bnf:133-134`) requires a `ScalarVariable`,
and `ScalarVariable` (`docs/chalk-bootstrap.bnf:271-275`) requires a
name (`/\$[a-zA-Z_]\w*.../` and friends). Bare `$` is not admitted.

**Suggested remediation shape:** Add a placeholder alternative to
either `ScalarSignatureParam` or `ScalarVariable`. Most narrowly:

```
ScalarSignatureParam ::= ScalarVariable
    | ScalarVariable _ /=/ _ Expression
    | /\$/ ;             # anonymous placeholder
```

The narrow form keeps `$` admissible only as a signature parameter,
not as an expression-position scalar. This matches Perl 5.42's
`use feature 'signatures'` semantics: anonymous slot in formal
parameter list, never elsewhere.

**Side effects of the fix:** None expected — `$` outside signature
context is already rejected by `ScalarVariable`'s regex. The narrow
form contains the change to one production.

### Gap 3: `q(...)` and `qq(...)` paren-delimited quote-like ops

**Trigger:** `my $x = q(abc);`, `my $x = qq(abc);`.

**Site count and locations:** 3 sites total in
`lib/Chalk/Bootstrap/BNF/Target/C.pm` and
`lib/Chalk/Bootstrap/BNF/Target/XS.pm` (per the maturity audit plan
`docs/plans/2026-04-24-maturity-audit-plan.md:171-172`).

**Boolean-rejects evidence:** `StringLiteral`
(`docs/chalk-bootstrap.bnf:297-303`) admits `q\s*\{...}` and
`q\s*[...]` and the `qq` equivalents — but not `q(...)` or `qq(...)`.
Probe of `q(abc)` shows Boolean=1 because the string parses as
`CallExpression(q, (abc))` (a builtin-style call to a function
named `q`); the full filter stack rejects via TypeInference's
keyword-rejection logic. So Boolean accidentally admits a wrong
parse, which TypeInference catches. This is an Audit 1 gap (no
correct grammar production exists) that masquerades as Audit 2 by
accidental admission.

**Suggested remediation shape:** Add paren-delimited alternatives to
`StringLiteral`:
```
StringLiteral ::= ...existing alts...
    | /q\s*\((?:[^)\\]|\\.)*\)/
    | /qq\s*\((?:[^)\\]|\\.)*\)/ ;
```

**Side effects of the fix:** Bracketed regex `q\s*\(` will overlap
with `CallExpression(q, ...)` at the Boolean level — the new alt
will produce a derivation that the existing CallExpression alt also
admits. TypeInference already rejects the latter, so this should
collapse cleanly. Verify with a tie probe.

### Gap 4: `qr{...}` and `tr/.../.../` regex/transliteration

**Trigger:** `my $re = qr{foo};`, `$x =~ tr/a/b/;`.

**Site count and locations:** Not surveyed — out of conformance
corpus scope per the maturity audit. Documented here because they
came up in the overlap probe, in case the broader self-hosting goal
expands.

**Boolean-rejects evidence:** `RegexLiteral`
(`docs/chalk-bootstrap.bnf:305-310`) admits `qr/.../`, `qr\s*\{...\}`
is absent. `tr/.../.../`  is absent entirely.

**Suggested remediation shape:** Defer until in scope. Out of scope
for self-hosting per
`docs/architecture/ambiguity-classes.md:226-231`.

### Gap 5: `do { ... }` admitted as CallExpression, not as
statement-level construct

**Trigger:** `do { 1 };`.

**Site count and locations:** Not surveyed. Reported because Boolean
parses `do { 1 }` successfully — but as `CallExpression(do, BLOCK)`,
treating `do` as an ordinary identifier. The `do BLOCK` and
`do EXPR` forms (file inclusion / block evaluation) are not
distinguished. `KeywordTable` does not list `do` in its keyword set
(verified via probe).

**Suggested remediation shape:** If `do BLOCK` is in scope,
add a dedicated production. If not in scope, document the
restriction and add `do` to the keyword set so the wrong-shape
parse is rejected at the TypeInference layer.

**Cross-reference:** Possibly an Audit 2 issue
(TypeInference / KeywordTable gap) more than an Audit 1 issue.

### Gap 6: keywords admitted as bare expression atoms

**Trigger:** `my $x = my;`, `my $x = sub;`, `my $x = field;`,
`my $x = our;`, `my $x = state;`, `my $x = local;`.

**Site count and locations:** Probe-only — these are all
syntactically invalid programs. Six keywords (`my`, `our`, `state`,
`local`, `sub`, `field`) parse as `QualifiedIdentifier` atom under
Boolean, then are rejected by TypeInference. Other keywords
(`class`, `method`, `if`, `unless`, `while`, `return`, `try`,
`catch`, etc.) parse all the way through both Boolean and full
stack. This is grammar over-permissiveness — see the
"Over-permissiveness" section below for the broader pattern.

## Pseudo-ambiguities beyond the documented classes

The seven documented classes are at
`docs/architecture/ambiguity-classes.md:25-176`. Note the document
header says "seven known classes"
(`docs/architecture/ambiguity-classes.md:6`) but the maturity-audit
plan refers to "the nine documented ambiguity classes"
(`docs/plans/2026-04-24-maturity-audit-plan.md:6`); there is
documentation drift here. The seven classes in `ambiguity-classes.md`
are: Precedence, Keyword/identifier, Block/hash, Regex/division,
Named-unary/list-op, Unary/binary minus, map-grep-sort BLOCK/EXPR.

Below are pseudo-ambiguities the audit identified that are not in
those seven.

### Item 1: `ParenExpr` alt 1 vs alt 2 (single-element list)

**Tokens admitted by both:** `(EXPR)` matches both
`/\(/ _ Expression _ /\)/` and `/\(/ _ ExpressionList _ /\)/` when
the list contains exactly one Expression. See `docs/chalk-bootstrap.bnf:167-169`.

**Currently resolved by:** Indeterminate. Both alts produce identical
token shapes; downstream the resulting Context shape may differ
(single-Expression vs ExpressionList-of-one). No semiring is
documented as resolving this overlap.

**Recommendation:** Tighten the grammar — alt 2 should require the
list to contain at least two elements, or alt 1 should be removed
since `Expression` is admitted by `ExpressionList`'s first
alternative (`docs/chalk-bootstrap.bnf:150`). The two-line
duplication is the kind of redundancy the maturity-audit plan
("Every rule should be the minimum shape describing valid token
sequences" — `2026-04-24-maturity-audit-plan.md:218-220`) flags.

### Item 2: `ExpressionStatement` alt 1 vs alt 2 (single expression)

**Tokens admitted by both:** A single Expression matches both
`Expression` (alt 1) and `ExpressionList` (alt 2 — which has its
own first alt of `Expression`). See `docs/chalk-bootstrap.bnf:55-57`.

**Currently resolved by:** Same shape, indeterminate resolution.

**Recommendation:** Same as Item 1 — alt 2 should require two or
more elements, or alt 1 should be dropped. Document if intentional.

### Item 3: `MethodCall` no-args vs with-empty-args

**Tokens admitted by both:** None directly, but `$obj->method` and
`$obj->method()` are distinct alternatives
(`docs/chalk-bootstrap.bnf:226` vs `225`) with alt 2 a strict prefix
of alt 1. Similarly `$obj->$m` vs `$obj->$m()` (`227-228`). Earley
will produce both up through the prefix, then commit on the trailing
token. Not strictly an ambiguity, but adds parse-time cost. Symmetric
with `Subscript` alt 3 (coderef call) which also has trailing args.

**Currently resolved by:** Earley's deterministic completion
mechanics — the trailing token (`(` vs `;` etc.) selects.

**Recommendation:** Document as design intent. No bug.

### Item 4: `q(...)` admitted as CallExpression-shaped

**Tokens admitted by both:** `q(abc)` parses as
`CallExpression(QualifiedIdentifier="q", ParenExpr="(abc)")` —
because `q` is a valid identifier and `(abc)` is a valid expression
list. The grammar has no production for `q(...)` quote-like
operator. See Gap 3 above.

**Currently resolved by:** TypeInference rejects `q` as an
identifier — but only if the keyword table includes it in the
right capacity. Per the probe, full stack rejects `q(abc)`, so the
filtering works. Same applies to `qq(abc)`, `qr(abc)`, `m(abc)`,
`s(...)(...)`, `tr(...)(...)`.

**Recommendation:** Treat as Gap 3 (grammar incompleteness, not
intentional ambiguity). Not a 10th-class candidate.

## Grammar over-permissiveness (admits malformed inputs)

These are not classical ambiguities — they are cases where the
grammar accepts inputs that aren't syntactically valid Perl. The
parser succeeds; the result is structurally meaningless or
non-roundtrippable.

### Over-1: Multi-trailing-comma in `ExpressionList`

**Trigger:** `(1,,)`, `(1,,,)`, `[1,2,,]`, `{a=>1,,}`, `foo(1,,)`.

**Cause:** `ExpressionList` alt 4 is `ExpressionList _ /,/`
(`docs/chalk-bootstrap.bnf:153`). Alt 4 allows the LHS to itself
be the result of alt 4, so any number of trailing commas chain.

**Recommendation:** Alt 4 should require the LHS to be the result
of a non-trailing-comma alt. Most direct fix: replace alt 4 with a
distinct nonterminal `ExpressionListWithOptionalTrailingComma`:
```
ExpressionListBody ::= Expression
    | ExpressionListBody _ /,/ _ Expression
    | ExpressionListBody _ /=>/ _ Expression ;
ExpressionList ::= ExpressionListBody | ExpressionListBody _ /,/ ;
```
This keeps trailing-comma support but bans `,,`.

### Over-2: Multi-trailing-comma in `SignatureParams`

**Trigger:** `sub f($a,,) { 1 }`, `sub f($a,,,) { 1 }`.

**Cause:** Same shape as Over-1. `SignatureParams` alt 3 is
`SignatureParams _ /,/` (`docs/chalk-bootstrap.bnf:128`) and
chains.

**Recommendation:** Same shape as Over-1.

### Over-3: Lone semicolons admitted as statement chain

**Trigger:** `;;;`, `;;`.

**Cause:** `StatementItem` alt 3 is `/;/` (`docs/chalk-bootstrap.bnf:30`).
Each lone `;` is a valid `StatementItem`; multiple chain via
`StatementList`'s left-recursion (`25-26`).

**Recommendation:** This is harmless for self-hosting and matches
Perl 5's behavior (`;` is the empty statement). Document as
intentional.

### Over-4: Bare regex `/foo/` admitted as statement-position
expression

**Trigger:** `/foo/;`, `m/foo/;`.

**Cause:** `RegexLiteral` is in `Literal` is in `Atom` is in
`Expression`. `/foo/;` therefore parses as `ExpressionStatement` of
the regex literal. This is a Class 4 question: under what context
is bare `/foo/` valid as an expression? Perl admits it when there
is an implicit `$_ =~`. The grammar does not constrain context;
the full filter stack (TypeInference / Structural) must.

**Recommendation:** Verify with Audit 2 that Class-4 resolution
extends to statement-level bare regex. The Boolean-side admission is
correct (it's the Class 4 ambiguity); the question is whether
TypeInference uses position information to type bare regex
correctly.

## Documented-class shape verification

Each class was exercised with the canonical input from
`docs/architecture/ambiguity-classes.md`. All examples were parsed
through `build_perl_recognizer` (Boolean only) and
`build_perl_concise_parser` (full stack with `tie_log`
instrumentation). Results below.

### Class 1: Precedence

**Inputs tested:** `$a + $b * $c`, `$x || $y && $z`,
`$a ? $b : $c ? $d : $e`, `$a = $b = $c`.

**Boolean accepts:** Yes for all four.
**Full-stack accepts:** Yes for all four.
**Unresolved ties:** 0 in all four cases.

**Mismatch?** No. Class 1 resolves cleanly.

### Class 2: Keyword vs identifier

**Inputs tested:** `class Foo { }`, `class => "Foo"`, `return $x`.

**Boolean accepts:** Yes for all three.
**Full-stack accepts:** Yes for all three.
**Unresolved ties:** 0.

**Mismatch?** No. Class 2 resolves cleanly. See Gap 6 — six
keywords are admitted as bare atoms by Boolean but rejected by full
stack; this verifies that TypeInference's keyword rejection works
for those, but it also exposes that the grammar admits more
keyword-as-atom cases than the documented Class 2 examples.

### Class 3: Block vs hash constructor

**Inputs tested:** `if ($x) { $y }`, `my $h = { a => 1 }`,
`return { a => 1 }`, `{}` (in `my $h = {}`).

**Boolean accepts:** Yes for all four.
**Full-stack accepts:** Yes for all four.
**Unresolved ties:** 0.

**Mismatch?** No. Class 3 resolves cleanly.

**Bonus observation:** Top-level `{a => 1}` parses as a Block (via
StatementItem→CompoundStatement→Block), not as a HashConstructor —
because at top-level `{...}` is not in expression position. This is
a Class 3 case, but resolved by structural position (statement
vs expression), not by the Structural semiring's `is_block` /
`is_hash` tags.

### Class 4: Slash as div vs regex

**Inputs tested:** `my $re = /foo/`, `my $x = $a / $b`,
`$x =~ /foo/`.

**Boolean accepts:** Yes for all three.
**Full-stack accepts:** Yes for all three.
**Unresolved ties:** 0.

**Mismatch?** No. Class 4 resolves cleanly.

### Class 5: Named unary vs list operator

**Inputs tested:** `defined $x + 1`, `print $x + 1`,
`push @arr, $x`, `keys %h + 1`.

**Boolean accepts:** Yes for all four.
**Full-stack accepts:** Yes for all four.
**Unresolved ties:** 0.

**Mismatch?** No. Class 5 resolves cleanly.

### Class 6: Unary minus vs binary minus

**Inputs tested:** `my $x = -5`, `my $x = 3 - 2`,
`my $x = -$y + 3`, `my $x = 3 - -$y`.

**Boolean accepts:** Yes for all four.
**Full-stack accepts:** Yes for all four.
**Unresolved ties:** 0.

**Mismatch?** No. Class 6 resolves cleanly.

### Class 7: map/grep/sort BLOCK vs EXPR

**Inputs tested:** `map { $_->name } @items`,
`sort { $a <=> $b } @items`, `sort @items`,
`grep { defined $_ } @items`.

**Boolean accepts:** Yes for all four.
**Full-stack accepts:** Yes for `map`, `sort BLOCK`, `sort no-block`.
**No** for `grep { defined $_ } @items` — Boolean accepts but full
stack rejects.

**Unresolved ties:** 0 even on the failing case.

**Mismatch?** Yes — `grep { defined $_ } @a` is grammar-recognized
but semiring-rejected. This is an **Audit 2 finding** (semiring
rejects valid input), not Audit 1. Cross-reference: include in the
Audit 2 input list. The other `grep` shapes (`grep { 1 } @a`,
`grep { $_ } @a`) succeed.

## Cross-document drift found

### Drift 1: `ambiguity-classes.md` says seven, audit plan says nine

`docs/architecture/ambiguity-classes.md:6` says "seven known
classes." `docs/plans/2026-04-24-maturity-audit-plan.md:6` and
the brief itself reference "the nine documented ambiguity classes"
(`docs/plans/2026-04-25-audit-1-grammar-brief.md:91, 109`). The
file actually contains seven Class-numbered sections (Class 1
through Class 7), plus a "scope note" listing additional ambiguity
points not classified. The brief's nine likely refers to the seven
plus two excluded-by-restriction cases (indirect object, bareword)
mentioned at lines 14-23 of `ambiguity-classes.md`. Either the
classes file should be renumbered to nine or the audit plan should
say seven. Documentation drift.

### Drift 2: `-X` file tests claimed missing but actually admitted

`docs/plans/2026-04-24-self-hosting-scope-audit.md:282` says of
`-X` file tests: "Grammar gap. Not in grammar." The maturity-audit
plan (`docs/plans/2026-04-24-maturity-audit-plan.md:166-167`) lists
`-X` as a self-hosting blocker.

Probe verification: all 27 file test characters
(`efdrwxRWXoOzslpSbcugktTBAMC`) parse successfully under both
Boolean and full stack. The grammar production exists at
`docs/chalk-bootstrap.bnf:182`:
```
| /-[efdrwxRWXoOzslpSbcugktTBAMC]\b/ _ Expression
```
Added by commit `36fce12b` (2026-04-24 22:33). The scope audit
appears to have been written against a state pre-`36fce12b`. This
needs a doc update — `-X` file tests are not a self-hosting
blocker.

## Cross-references

### Audit 2 inputs (semiring-rejected, not grammar-rejected)

- `grep { defined $_ } @a` — Boolean accepts, full stack rejects.
  Class 7 case where the EXPR-form alt may be winning incorrectly.
- `q(abc)` parsed as `CallExpression(q, ...)` — TypeInference
  rejects because `q` is keyword-rejected, but the underlying issue
  is that the grammar should admit `q(...)` as a quote-like
  operator (Gap 3). Same applies to `qq`, `m`, `s`, `qr`, `tr`.
- Six keywords admitted as bare atoms (Gap 6) — `my`, `our`,
  `state`, `local`, `sort`(if), `sub`, `field`. Tests TypeInference's
  keyword rejection coverage.

### `ambiguity-classes.md` updates needed

- Resolve drift 1 (seven vs nine).
- Update drift 2 (`-X` file tests in scope, already admitted).
- Add notes for Items 1–4 above (pseudo-ambiguities not currently
  documented). At minimum: an "ExpressionList vs ParenExpr single-
  element shape redundancy" note, with a recommendation either way.
- Document the over-permissiveness cases (Over-1 through Over-4)
  separately under a "Grammar over-acceptance" subhead.

### `chalk-bootstrap.bnf` candidate edits (not made)

- `PostfixDeref` line 236: add `->@[expr]` alternative (Gap 1).
- `ScalarSignatureParam` line 133 or `ScalarVariable` line 271:
  admit anonymous `$` (Gap 2).
- `StringLiteral` line 297: add `q(...)` and `qq(...)` (Gap 3).
- `ExpressionList` line 150: tighten alt 4 against multi-trailing-
  comma chain (Over-1).
- `SignatureParams` line 126: same fix (Over-2).
- `ParenExpr` line 167: tighten alt 1 vs alt 2 (Item 1).
- `ExpressionStatement` line 55: tighten alt 1 vs alt 2 (Item 2).

None of these changes were made. Each is on the punch list for
remediation phase, owner's discretion.

## Acceptance criteria walkthrough

The brief lists five acceptance criteria
(`docs/plans/2026-04-25-audit-1-grammar-brief.md:201-211`):

1. **Both seed gaps verified via fresh Boolean-vs-full-stack
   probes** — Met. Probes ran fresh against the current grammar.
   Both reject under Boolean. See "Gap 1" and "Gap 2" above.

2. **Every rule in `docs/chalk-bootstrap.bnf` examined for
   alt-overlap** — Met. All 56 rules in the grammar were examined.
   Findings categorized into Items 1–4 (intentional or harmless
   overlaps) and Over-1 through Over-4 (over-permissiveness).

3. **Every documented ambiguity class exercised with a minimal
   example and the derivation count recorded** — **Partial**. The
   seven classes were exercised with canonical examples and tie
   counts recorded under the full filter stack. Derivation counts
   under Boolean alone were not recorded — see "Methodology
   limitation" above. Boolean's `add()` collapses ambiguity by
   returning its left operand, and the chart isn't externally
   accessible. Under the available signal (`tie_log`), all seven
   classes resolve cleanly with zero unresolved ties on canonical
   inputs. One canonical Class-7 input
   (`grep { defined $_ } @a`) parses Boolean-only but is rejected
   by the full stack — flagged as an Audit 2 input.

4. **Findings file committed to `worktree-pu` directly** — Met
   (commit follows this report).

5. **Subagent reports: punch list summary, no claims of "fixed" or
   "improved"** — Met. No production files touched. No tests added.
   No grammar edits made. All probe scripts have been deleted
   (`/tmp/audit1-*.pl` removed). The five reusable probe templates
   from the brief (`pattern-a-probe.pl`, etc.) are preserved.

## Punch list summary by category

- **Confirmed grammar gaps requiring extension:** 3 in scope for
  self-hosting (Gap 1 ->@[range]; Gap 2 anonymous-skip; Gap 3
  paren-quoted); 1 borderline (Gap 5 `do` block); 1 broad
  (Gap 6 keyword over-admission affecting six keywords); 1 deferred
  (Gap 4 `qr{}`/`tr/`).

- **Grammar over-permissiveness (admit malformed input):** 4 items
  (Over-1 ExpressionList multi-comma; Over-2 SignatureParams
  multi-comma; Over-3 lone semicolons (likely intentional);
  Over-4 bare regex statement (Class 4 verification needed)).

- **Pseudo-ambiguity items not in documented classes:** 4 items
  (Item 1 ParenExpr single-element overlap; Item 2
  ExpressionStatement single-element overlap; Item 3 MethodCall
  prefix-of-prefix (likely intentional); Item 4 quote-like
  parsed as call (subset of Gap 3)).

- **Cross-document drift:** 2 items (seven vs nine ambiguity
  classes; `-X` file tests already admitted).

- **Audit 2 inputs (semiring concerns surfaced during probing):**
  3 items (`grep { defined $_ } @a` rejection; quote-like-as-call
  rejection; keyword-as-atom rejection coverage).

Total punch-list items: 17, of which 4–5 are likely worth acting on
in the near term (Gaps 1, 2, 3 for self-hosting; Over-1 and Over-2
for grammar tightening). The rest are documentation, deferred, or
Audit 2 inputs.
