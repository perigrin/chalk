# Audit 1 — Grammar (subagent brief)

**Date:** 2026-04-25
**Companion to:** `docs/plans/2026-04-24-maturity-audit-plan.md`
**Status:** Brief, ready to dispatch.

## What this audit is

A read-only investigation that produces a punch list of grammar
issues. The audit does not fix anything. It produces a markdown
report (this file's sibling, suffix `-findings.md`) and stops.

Output owner is perigrin. The audit's output becomes input for a
later, separate remediation phase.

## Oracle

The oracle for this audit is the existing conformance harness
(`t/grammar-conformance.t`) plus the Boolean-vs-full-stack
discriminator. Both are deterministic, both already exist, both
work without the audit having to build infrastructure.

For any failing file in `lib/`, the audit determines whether the
failure is grammar-rejected (Boolean alone says no) or
semiring-rejected (Boolean alone says yes, full stack says no).
Grammar-rejected failures belong to this audit. Semiring-rejected
failures belong to Audit 2 and are explicitly out of scope here.

## Seed data — confirmed grammar gaps

Pre-isolated by probe sequence ending 2026-04-25 02:14. Both are
narrow, both have one site each.

### Gap 1: `->@[range]` postfix array slice

**Test case:**

```perl
my @x = map { $_ } $arr->@[0..2];   # GRAMMAR REJECTS (Boolean)
```

**Single site:** `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm:26`
(was `$semirings->@[0 .. $#{ $semirings } - 1]`; reverted in
commit `cf14d82e` as part of A.1 cleanup, replaced with
`->@*` + `pop` workaround. Production code currently does not
use this syntax — the gap is documented but not load-bearing.)

**Investigation needed:**

- Confirm the rule producing PostfixDeref. Currently:
  ```
  PostfixDeref ::= Expression _ /->/ _ /@\*/
      | Expression _ /->/ _ /%\*/
      | Expression _ /->/ _ /\$\*/
      | Expression _ /->/ _ /\$#\*/ ;
  ```
  Postfix array slice (`->@[expr]`) is absent. Audit should propose:
  - Whether to add it, knowing TypeInference also filters it (per
    A.1's `->@[...]` round-trip in `36fce12b`/`9fde79e4`).
  - Whether the symmetric forms (`->%[...]` hash slice via array
    keys; `->@{...}` hash slice via list keys) need entries too.

**Cross-reference:** Pattern 6 from A.1's `t/bootstrap/grammar-extensions.t`
TODO tests, which were removed in `cf14d82e`. The gap exists in
the grammar; the question is whether it should be closed.

### Gap 2: Anonymous-skip signature parameter `$,`

**Test case:**

```perl
my sub foo($, $real) { return $real; }   # GRAMMAR REJECTS (Boolean)
```

**Single site:** `lib/Chalk/Bootstrap/IR/Optimizer.pm:10`
(`sub collapse_phi($, $phi) { ... }`).

**Investigation needed:**

- Locate the signature grammar rule (search for `param` /
  `Signature` in `docs/chalk-bootstrap.bnf`).
- Determine whether the grammar admits `$` as a placeholder param.
  Test cases:
  - `sub f($, $b)` (skip first)
  - `sub f($a, $)` (skip last)
  - `sub f($, $, $c)` (skip multiple)
- Is `$` a real Perl signature feature in 5.42? Verify against
  `perldoc perlsub` semantics before concluding the grammar should
  accept it.

## Audit 1 also surveys: pseudo-ambiguity beyond the documented nine

`docs/architecture/ambiguity-classes.md` documents nine intentional
ambiguity classes. The grammar may admit additional unintentional
overlaps. Audit 1's secondary task:

- Enumerate every rule in `docs/chalk-bootstrap.bnf`.
- For each, identify alternatives whose token shapes overlap with
  alternatives in other rules.
- For each overlap, classify:
  - Belongs to one of the documented nine → fine, note which.
  - Not in the nine, but resolved by a semiring → undocumented
    ambiguity; flag for `ambiguity-classes.md` update.
  - Not in the nine, not resolved → grammar bug.

This survey produces a list, not a fix. The list goes into the
findings report.

## Audit 1 also surveys: alt-shape correctness for the documented nine

For each of the nine documented ambiguity classes:

- Identify the rule(s) and alternative(s) the class lives in.
- Construct a minimal example exercising the ambiguity.
- Verify the parser produces the documented number of derivations
  under Boolean alone (e.g., Class 5 nested ternary should produce
  N derivations, not 1).
- Note any class where the grammar produces a different count than
  the documentation expects.

Again, this produces a list. No fixes.

## Constraints — what this audit MUST NOT do

- Do NOT modify `lib/`, `t/`, `docs/chalk-bootstrap.bnf`, or
  any production file.
- Do NOT add tests except internal scratch probes (delete them
  before finishing).
- Do NOT extend grammar to make failing files parse. The audit's
  job is to document, not extend.
- Do NOT touch `lib/Chalk/Bootstrap/DepChaser.pm`. Excluded as
  transitional per maturity plan.
- Do NOT analyze files in `script/`. Out of conformance corpus.
- Do NOT propose semiring changes. Audit 2 owns those.
- Do NOT build a behavioral-equivalence harness. That's a separate
  phase, not part of any audit.
- If you find yourself writing "let me just fix this small thing,"
  stop and add it to the punch list instead.

## Tools available

- `Read`, `Grep`, `Glob`, `Bash` (for diagnostic runs only)
- `t/grammar-conformance.t` (already passes 121 of 148 files)
- The Boolean-vs-full-stack probe pattern (see
  `t/bootstrap/lib/TestPipeline.pm` — `build_perl_recognizer` for
  Boolean only, `build_perl_concise_parser` for full stack)
- The probe scripts already written in `/tmp/`
  (`pattern-a-probe.pl`, `pattern-a-probe2.pl`,
  `pattern5-isolate.pl`, `ternary-min.pl`, `ternary-min2.pl`) —
  reusable as templates for new probes.

## Skills required

- `superpowers:writing-perl-5.42.0`
- `superpowers:systematic-debugging`
- `chalk-development`

## Output

A markdown file at:
`docs/plans/2026-04-25-audit-1-grammar-findings.md`

Structure:

```markdown
# Audit 1 — Grammar Findings

## Summary
- Grammar gaps confirmed: N
- Pseudo-ambiguities discovered beyond the documented nine: N
- Documented-class shape mismatches: N

## Confirmed grammar gaps
### Gap N: <short name>
**Trigger:**
**Site count and locations:**
**Boolean-rejects evidence:**
**Suggested remediation shape:**
**Side effects of the fix:**

## Pseudo-ambiguities beyond the documented nine
### Item N: <rule>: <alt> overlaps with <rule>: <alt>
**Tokens admitted by both:**
**Currently resolved by:** (semiring | unresolved)
**Recommendation:** (document as 10th class | grammar tightening | flag as bug)

## Documented-class shape verification
### Class N: <name>
**Expected derivations for canonical input:** N
**Actual:** N
**Mismatch?** (yes | no)
**Notes:**

## Cross-references
- Audit 2 inputs: ...
- ambiguity-classes.md updates needed: ...
```

Length target: 1500–3000 words. Findings before opinions.

## Acceptance — how the audit knows it's done

1. Both seed gaps verified via fresh Boolean-vs-full-stack probes
   (don't trust the brief; re-run).
2. Every rule in `docs/chalk-bootstrap.bnf` examined for
   alt-overlap.
3. Every documented ambiguity class exercised with a minimal
   example and the derivation count recorded.
4. Findings file committed to `worktree-pu` directly.
5. Subagent reports: punch list summary, no claims of "fixed" or
   "improved."

## Reading list before starting

- `docs/plans/2026-04-24-maturity-audit-plan.md` — master plan
- `docs/architecture/ambiguity-classes.md` — the nine documented
  classes
- `docs/chalk-bootstrap.bnf` — the grammar
- `docs/plans/2026-04-24-self-hosting-scope-audit.md` — what the
  scope-audit pass concluded; some findings overlap
- `docs/plans/2026-04-24-toke-sweep-undocumented-ambiguity.md` —
  the 22 toke.c points; relevant for "what else is unintentionally
  admitted"
- `t/grammar-conformance.t` — the harness
- `t/bootstrap/lib/TestPipeline.pm:165–177` — `build_perl_recognizer`
