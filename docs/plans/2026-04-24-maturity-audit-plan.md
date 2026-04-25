# Chalk Maturity Audit — Plan for Next Sessions

**Status:** Plan document. No audits executed yet.

**Author:** perigrin + Claude, 2026-04-24.

**Scope context:** Earley parsing, the nine documented ambiguity
classes (seven resolved by filtering semirings, two excluded by
grammar restriction — see `docs/architecture/ambiguity-classes.md`),
and the filter-semiring architecture are all verified sound. What
remains is implementation maturity across four layers — grammar,
semirings, MOP+IR, and codegen — plus a small, well-scoped list of
grammar gaps blocking self-hosting.

## What this session produced

Four audit reports committed during the session ending 2026-04-24:

1. `2026-04-23-earley-reification-overwrites-add-merge-design.md` —
   early investigation that turned out to be chasing a
   Boolean-standalone bug unused in production.
2. `2026-04-24-option-b-grammar-refactor-postmortem.md` — captures
   the failed Option B grammar refactor and corrects the
   "inherent to Perl" overreach.
3. `2026-04-24-semiring-contract-drift.md` — documents that
   Precedence, Structural, and TypeInference don't honor
   `(Context, Context) -> Context`; FilterComposite papers over.
4. `2026-04-24-ambiguity-decision-record.md` — verifies the nine
   documented ambiguity classes are correctly classified; includes
   Perl citations.
5. `2026-04-24-toke-sweep-undocumented-ambiguity.md` — identifies
   22 additional Perl ambiguity points outside the documented nine.
6. `2026-04-24-self-hosting-scope-audit.md` — narrows the 22
   points to 3 real blockers for self-hosting.

Together these establish the starting position for the real audit
and implementation work.

## The four maturity audits (reading order)

Each of these layers has a coherent architecture but incomplete
implementation. The audits should run in this order because later
audits depend on earlier ones being complete.

### Audit 1: Grammar

**Scope**: verify the grammar admits exactly what it should and
nothing more.

**Key questions**:
- Does the grammar admit unnecessary pseudo-ambiguities beyond the
  nine documented classes? (The `ExpressionList(single)` overlap
  eliminated in an Option B attempt is one example.)
- Do any of the nine admitted classes have grammar-level
  unsoundness (e.g., alt shapes that don't match the syntax they
  claim to describe)?
- Are the three self-hosting blockers (`-X` file tests, paren-
  delimited quote ops) the complete list, or do other blockers
  exist in `lib/`?

**Method**:
- Enumerate every rule and alternative; for each, check whether
  any other alternative admits the same token shape.
- Document intentional ambiguities (the nine) vs unintentional
  (grammar bugs).
- Audit the 22 undocumented points specifically against current
  grammar behavior — which are already admitted silently (via
  existing rules) vs which are outright rejected?

**Decision rule** for what to keep in the grammar vs move elsewhere:
1. **Rule-explosion test** — does grammar-encoding multiply rules
   combinatorially? (Precedence paradigm.) → Semiring.
2. **Layer-violation test** — does grammar-encoding require
   semantic knowledge the grammar shouldn't have? → Semiring.
3. **Neither triggers** → Grammar is a candidate for encoding.

**Expected outcome**: A catalogue of every pseudo-ambiguity the
grammar admits, with disposition per case (keep and document,
remove and simplify, move to semiring, restrict).

### Audit 2: Semirings

**Scope**: verify each semiring's implementation matches its
architectural role.

**Key questions**:
- Is each semiring contract-compliant? (`(Context, Context) -> Context`.)
- For each documented ambiguity class, does the semiring
  responsible for it produce correct resolutions on a
  representative corpus?
- Where is work leaking across semiring boundaries? (Structural
  currently absorbs some Class 5 work that belongs to TypeInference.)
- Is TypeInference a complete type-inference engine, or a
  tag-checker labeled "type inference"? (Per perigrin's framing: a
  sketch, not a complete implementation.)

**Method**:
- For each semiring, compare stated responsibility (per
  `ambiguity-classes.md` and design docs) against observed
  responsibility (code and test behavior).
- Inventory `_slot_val` helpers and FilterComposite's special-
  cased handling — each of these is evidence of contract drift.
- Build a corpus that exercises each of the seven semiring-resolved
  ambiguity classes with canonical inputs; verify each is resolved
  by the declared resolver. (Classes 8 and 9 are excluded by
  grammar restriction and have no semiring resolver to exercise.)

**Expected outcome**: Per-semiring gap list. Estimated work per
semiring to reach contract compliance and full role implementation.

### Audit 3: MOP + IR

**Scope**: verify the MOP and IR layers' implementation maturity.

**Key questions** (from CLAUDE.md's own warnings):
- Is the polymorphic migration complete? (Reported ~80% complete,
  with ~61 `make('Constructor', ...)` calls remaining in
  `Actions.pm`.)
- Is `Shim.pm` still present? Can it be deleted?
- Does codegen use graph-walk (`_build_method_graph`) or still
  fall back to `body()`?
- Is `compat_class` on `Chalk::IR::Node` dead code yet?
- What's the status of "prototype" commits (e.g., `c7361f3c`)?
- Does **DepChaser** exist because MOP can't answer dependency
  queries? If so, MOP completion retires DepChaser.

**Method**:
- Audit the 2026-04-04 migration plan and Phase 4 structural split
  plan against current code state.
- Inventory all compat/transitional code paths.
- Identify which pieces of MOP completion specifically unblock
  DepChaser removal.

**Expected outcome**: A punch list of MOP+IR completion work,
ordered by what unblocks what downstream.

### Audit 4: Codegen

**Scope**: determine whether codegen's architecture is correct or
whether it's accreted workaround.

**Key questions**:
- The Perl-to-C compiler has known gaps (e.g., list destructuring)
  that EmitHelpers patches over via regex substitution. How many
  such patches exist? Are they all symptoms of compiler
  incompleteness, or architectural design?
- Is the distinction between "Perl-to-C compiler" and "EmitHelpers
  post-processor" principled, or does it exist because the compiler
  isn't finished?
- How do regex fixups interact — are they independent or
  load-bearing on each other?

**Method**:
- Inventory every `_fixup_*` method in EmitHelpers.
- For each, determine whether it patches a compiler gap (the
  principled answer: fix the compiler) or implements a design
  decision (the principled answer: document and test).
- Identify whether the codegen's current layering survives
  completion of the layers below.

**Expected outcome**: A judgment on whether codegen has a
recoverable architecture with implementation gaps, or whether it
needs re-architecture after layers 1-3 are complete.

## Self-hosting grammar work (independent of audits)

Separate from the four audits above, a small amount of grammar
work is needed to complete self-hosting. This can happen in
parallel with the audits — it doesn't depend on them:

1. **`-X` file test operators** — grammar extension. 2 sites in
   `Runtime.pm`. A few alts added to `UnaryExpression`.
2. **Paren-delimited `q()`/`qq()`** — grammar extension. 3 sites
   in BNF targets. Add parentheses to the admissible delimiter set
   for quote-like operators.

Both are small, well-scoped, and independently verifiable. Should
unblock Chalk parsing its own source.

**Not part of self-hosting**: readline, `local $/;`, `eval
"STRING"` — all concentrated in `DepChaser.pm` which is
transitional. The proper fix is MOP completion removing DepChaser,
not teaching the grammar features Chalk's subset doesn't aim to
support.

## Correctness infrastructure (can start anytime)

Two test-infrastructure investments documented in the Option B
postmortem as flaw classes 2 and 4 — both implementable
independently:

- **Semiring-law tests** (flaw class 2): each semiring's `add` and
  `multiply` must satisfy the semiring laws. Property-based tests
  that exercise commutativity, associativity, distributivity,
  zero/one identity. Estimated 2-3 days. Currently no such tests
  exist.
- **Structural-tag-contract tests** (flaw class 4): parse a
  representative corpus and assert specific `annotations->{structural}`
  values at specific rule completions. Any grammar change that
  shifts alt indices would immediately fail these tests.
  Estimated 1-2 days.

Both act as regression guards for work done in audits 1 and 2.

## Principles reaffirmed this session

These should inform all future audit and implementation decisions:

1. **Grammar encodes syntax. Semirings encode semantics.** If the
   grammar needs to know what a specific builtin does, that's a
   layer violation.

2. **Filter order is performance optimization, not correctness.**
   Reordering the stack shouldn't change which derivation is the
   correct parse — only which semiring expresses the preference
   first. The correctness invariant is weaker: no semiring may
   produce a wrong answer.

3. **Every rule should be the minimum shape describing valid token
   sequences.** Multiple alternatives encoding semantic
   distinctions of the same shape is redundancy at the grammar
   layer.

4. **`(Context, Context) -> Context` is the semiring contract.**
   Three semirings currently violate it; FilterComposite papers
   over. Bringing them into contract is real work but unblocks
   cleaner reasoning about semiring composition.

5. **Transitional workarounds should be named and marked.**
   DepChaser is a workaround for incomplete MOP, not a permanent
   feature. Its ABOUTME is updated to say so.

6. **Rationalization traps to avoid**: "X is inherent to Perl"
   (check whether it's inherent to our formalization instead);
   "Boolean is anomalous" (check whether it's the one doing the
   contract correctly); "this is a quick fix" (check whether it's
   a bandage on another unaddressed issue).

## Starting conditions for next session

- All work from this session committed (see git log for the
  chronological list, or the audit-report files for the findings).
- Task list is empty — no dangling work.
- Semiring tests pass; production Perl IR parsing works; synthetic
  probe passes. Baseline is stable.
- Six design documents exist in `docs/plans/2026-04-2[34]-*.md`
  covering the investigations. Worth reading before resuming.
- `DepChaser.pm`'s ABOUTME now notes transitional status.
- `ambiguity-classes.md` updated with the 22-point scope note and
  the corrected Invariant #2.

## Suggested next-session order

1. **Open with the small grammar work** — `-X` file tests and
   paren-delimited quote ops. 1-2 hours. Concrete, satisfying,
   moves self-hosting forward.

2. **Then Audit 1 (grammar)** — build on the just-completed
   grammar work with eyes already in that layer.

3. **Or alternatively**, start with the structural-tag-contract
   tests (flaw class 4) as a regression harness before any grammar
   changes. Arguably the safer order.

4. **Audits 2, 3, 4 in order** as each unblocks the next.

The order isn't rigid; these are independent enough that any of
them could happen first. The rough principle: **start with small
wins to stay grounded**, then tackle the bigger audits once there's
momentum.
