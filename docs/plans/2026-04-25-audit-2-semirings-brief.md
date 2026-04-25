# Audit 2 — Semirings (subagent brief)

**Date:** 2026-04-25
**Companion to:** `docs/plans/2026-04-24-maturity-audit-plan.md`
**Status:** Brief, ready to dispatch.

## What this audit is

A read-only investigation that produces a punch list of semiring
issues. The audit does not fix anything. It produces a markdown
report (this file's sibling, suffix `-findings.md`) and stops.

This is the load-bearing audit for Phase A.2. Three semiring-level
filter bugs explain ~25 of the 27 currently-failing files in
`t/grammar-conformance.t`. The audit's primary job is to identify
the rejecting semiring per pattern and document why and how each
rejection happens.

## Oracles

Three independent oracles, all available today:

1. **Boolean-vs-full-stack discriminator** — ownership oracle.
   Decides "grammar bug or semiring bug" deterministically. Pattern
   in `t/bootstrap/lib/TestPipeline.pm`: `build_perl_recognizer`
   for Boolean only, `build_perl_concise_parser` for full stack.

2. **Per-stage stack discriminator** — extension of #1 to identify
   which semiring rejects. Build FilterComposite parsers with
   subsets of the stack:
   - `[Boolean]`
   - `[Boolean, Precedence]`
   - `[Boolean, Precedence, TypeInference]`
   - `[Boolean, Precedence, TypeInference, Structural]`
   - `[Boolean, Precedence, TypeInference, Structural, SemanticAction]`

   The first stack that rejects identifies the rejecting semiring.

3. **Semiring laws** — internal-invariant oracle. For each semiring,
   `add` and `multiply` must satisfy commutativity (where
   declared), associativity, distributivity, and zero/one identity.
   Property-based tests against these laws catch contract drift.
   Currently no such tests exist; the audit identifies which laws
   each semiring should satisfy and documents existing violations
   (some already documented in `2026-04-24-semiring-contract-drift.md`).

## Seed data — three confirmed semiring filter bugs

Pre-isolated by probe sequence ending 2026-04-25 02:14. Each has a
minimal failing test case. The audit's first task is to identify
the rejecting semiring for each.

### Bug 1: Ternary expression as BLOCK of block-form builtin

**Minimal failing case:**

```perl
my @x = map { defined $_ ? $_ : 0 } (1, 2, 3);   # SEMIRING REJECTS
```

**Discriminator evidence (from probe `bcdq6g3ks`):**

| Variation | BLOCK content | Result |
|---|---|---|
| Ternary in BLOCK, lexical LIST | `defined $_ ? $_ : 0` | **fail** |
| Ternary in BLOCK, field LIST | same | **fail** |
| Ternary in BLOCK, postfix-deref LIST | same | **fail** |
| Identity BLOCK | `$_` | pass |
| Concat BLOCK | `$_ . "x"` | pass |
| String-interp BLOCK | `"$_"` | pass |
| Bare ternary (no map) | various | pass |
| Ternary inside `for (...) { ... }` body | various | pass |

**Site count:** ~12–15 files (the dominant pattern in the IR
metadata cluster: `MethodInfo`, `SubInfo`, `UseInfo`, `Rule`,
`FieldInfo`, `Node`, plus `BNF/Target/XS/AST/XSUB`, plus several
others where the binary-search probe pointed at `map { ... } $ref->@*`
sites).

**Hypothesis to test (NOT to assume):**

The rejecting semiring is most likely TypeInference or Structural,
because:
- Boolean accepts the construct (verified).
- Precedence is unlikely to filter at BLOCK boundaries (it operates
  on operator chains).
- SemanticAction shouldn't reject anything (it builds IR; failure
  there would be silent-error category).

Possible mechanisms:
- TypeInference: TernaryExpr's return type isn't unifying with
  what map's BLOCK expects (map BLOCK is treated as something other
  than "any expression returning the right type")
- Structural: TernaryExpr produces a structural shape (annotation)
  that the BLOCK-of-builtin context tags as incompatible

The audit confirms or refutes both, identifies the actual code
path, and reports.

### Bug 2: `qw(...)` as LIST argument to block-form builtin

**Minimal failing case:**

```perl
my %h = map { $_ => 1 } qw(a b c);   # SEMIRING REJECTS
```

**Discriminator evidence (from probe `b5ffm4q5w`, T7 in
`b2l32msr7`):**

- Single-line and multi-line `qw(...)` both fail in this context.
- Standalone `qw(...)` (assigned to array, no map) passes.
- Multi-line qw with operator-character contents fails the same
  way (e.g., `EmitHelpers.pm:758`'s
  `qw(>= <= > < ... && || // and or)`).

**Site count:** ~5 files. Concrete: `lib/Chalk/IR/Shim.pm:9`,
`lib/Chalk/IR/Serialize/JSON.pm:17`, `lib/Chalk/IR/NodeFactory.pm:83`,
`lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm:758`,
`lib/Chalk/Bootstrap/Perl/Actions.pm:28`.

**Investigation needed:**

- Does the trigger interact with Bug 1? (Both are "thing inside
  map BLOCK or LIST that the semirings filter.")
- Is the rejection because qw is being treated as a single token
  rather than a list, or because the TypeInference signature for
  block-form `map` doesn't accept whatever type qw returns?

### Bug 3: Postfix dereference in implicit numeric context

**Minimal failing case:**

```perl
for (my $i = 0; $i < $arr->@*; $i += 2) { last; }   # SEMIRING REJECTS
```

**Discriminator evidence (from probe `b5ffm4q5w`):**

- `scalar $arr->@*` (explicit context) passes.
- `$i < $arr->@*` (implicit numeric context) fails.

**Site count:** 1 (`lib/Chalk/Bootstrap/Perl/Target/C.pm:107`).

**Hypothesis:** TypeInference doesn't know `->@*` evaluates to
scalar count when in scalar/numeric context. The signature lookup
for `<` (numeric comparison) expects two numeric operands, and
the right-hand side `$arr->@*` carries an Array type tag instead
of a numeric one.

## Audit 2 also reviews: contract drift

`docs/plans/2026-04-24-semiring-contract-drift.md` documents that
Precedence, Structural, and TypeInference don't honor
`(Context, Context) -> Context`. FilterComposite papers over.

The audit's secondary task:

- For each violator, document the exact contract violation.
- For each, identify what the violator returns instead.
- For each, document FilterComposite's compensating logic.
- Determine whether bringing the violators into contract is a
  small fix (rename / wrap) or a structural change (per-semiring
  refactor).

This is documentation work, not refactoring. Output goes into the
findings report.

## Audit 2 also surveys: ambiguity ownership

Per `docs/architecture/ambiguity-classes.md`, each of the nine
documented classes is owned by a specific semiring. The audit
verifies that ownership claim:

- For each class, construct a minimal example.
- Disable the claimed-owner semiring (or substitute a no-op).
- Confirm the ambiguity now produces multiple derivations (the
  filter was load-bearing) OR the ambiguity still resolves (the
  ownership claim is wrong).

This produces a per-class assignment-vs-reality table.

## Audit 2 also surveys: TypeInference completeness

CLAUDE.md framing notes (`feedback_technical_debt_cleanup` memory):
TypeInference may be "a tag-checker labeled type-inference," not
a real type-inference engine. The audit determines:

- What types does TypeInference actually track? (Inventory the
  type tags it reads/writes.)
- What types does the documented architecture claim it tracks?
  (Per `docs/architecture/parsing-pipeline.md` and
  `chalk_canonical_description.md`.)
- Where do they differ?

This is a gap analysis, not a fix.

## Constraints — what this audit MUST NOT do

- Do NOT modify any production code (`lib/`, `t/`, `docs/`).
- Do NOT add semiring features.
- Do NOT add tests except internal scratch probes (delete them
  before finishing).
- Do NOT touch `lib/Chalk/Bootstrap/DepChaser.pm`.
- Do NOT analyze `script/` files.
- Do NOT propose grammar changes. Audit 1 owns those.
- Do NOT build the round-trip / behavioral-equivalence harness.
  That's a separate phase.
- If you find yourself writing "let me just fix this," stop and
  add it to the punch list.

## Tools available

- `Read`, `Grep`, `Glob`, `Bash` (diagnostic runs only)
- `t/grammar-conformance.t`
- The per-stage stack-discrimination pattern (build it from
  `TestPipeline.pm:135-163` by varying the `semirings => [...]`
  arrayref)
- The probe scripts already written in `/tmp/` — reusable
  templates

## Skills required

- `superpowers:writing-perl-5.42.0`
- `superpowers:systematic-debugging`
- `superpowers:root-cause-tracing`
- `chalk-development`

## Output

A markdown file at:
`docs/plans/2026-04-25-audit-2-semirings-findings.md`

Structure:

```markdown
# Audit 2 — Semiring Findings

## Summary
- Confirmed semiring filter bugs: 3 (seed) + N (discovered)
- Contract violations confirmed: 3 (seed) + N (discovered)
- Ambiguity-class ownership mismatches: N
- TypeInference completeness gaps: N

## Confirmed semiring filter bugs

### Bug N: <short name>
**Minimal failing case:**
**Per-stage rejection (Boolean | +Precedence | +TypeInference | +Structural | +SA):**
**Rejecting semiring:**
**Code path of rejection:**
  - File:line of the rejection logic
  - What value is returned (zero / undef / multiplicative-zero)
  - Why this construct produces zero
**Why this is the correct/incorrect behavior:**
**Suggested remediation shape:**
**Cross-effect on other patterns:**

## Contract violations
### Violation N: <semiring> does not honor <signature>
**Documented contract:**
**Actual return type:**
**FilterComposite compensation logic:**
**Cost of bringing into contract:** (small | medium | structural)

## Ambiguity-class ownership verification
### Class N: <name>
**Documented owner:**
**Actual resolver (verified by semiring-ablation probe):**
**Mismatch?** (yes | no)
**Notes:**

## TypeInference completeness gap analysis
### Tag/type N
**Tracked by code:** (yes | no)
**Documented as tracked:** (yes | no)
**Used by which downstream layer:**
**Gap:** (none | code-tracks-not-documented | documented-but-not-tracked)

## Cross-references
- Audit 1 inputs: ...
- Audit 3 inputs: ...
- ambiguity-classes.md updates needed: ...
- semiring-contract-drift.md updates needed: ...
```

Length target: 3000–6000 words. This audit has the broadest scope
and the deepest investigation. Findings before opinions.

## Acceptance — how the audit knows it's done

1. All three seed bugs have a confirmed rejecting semiring named
   with code-path evidence.
2. The three contract violations from
   `2026-04-24-semiring-contract-drift.md` each have a return-type
   inventory and FilterComposite-compensation analysis.
3. All nine documented ambiguity classes have ownership
   verification probes recorded.
4. TypeInference completeness gap analysis is at least surface-level
   complete.
5. Findings file committed to `worktree-pu` directly.
6. Subagent reports: punch list summary with rejecting semiring
   per bug. No claims of "fixed."

## Reading list before starting

- `docs/plans/2026-04-24-maturity-audit-plan.md` — master plan
- `docs/plans/2026-04-24-semiring-contract-drift.md` — known
  violations
- `docs/architecture/ambiguity-classes.md` — claimed ownership
- `docs/architecture/parsing-pipeline.md` — semiring stack
  architecture
- `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm` — the orchestrator
- `lib/Chalk/Bootstrap/Semiring/Precedence.pm`, `TypeInference.pm`,
  `Structural.pm`, `SemanticAction.pm`, `Boolean.pm` — the players
- `lib/Chalk/Bootstrap/Semiring/TypeInferenceActions.pm` — the
  per-rule type-computation actions
- `t/bootstrap/lib/TestPipeline.pm` — parser construction patterns
- Memory: `~/.claude/projects/-home-perigrin-dev-chalk/memory/MEMORY.md`
  — the project's accumulated wisdom about semiring behavior
