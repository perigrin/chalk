# T1 architecture plan — from HEAD to the spec, decomposed around prerequisites

**Date:** 2026-08-26
**Status:** PLAN. Replaces the slice-4 decomposition (4a–4e) of
`docs/plans/2026-08-24-loader-analysis-pipeline.md`, which failed build
verification (`docs/plans/2026-08-26-slice4-build-verification.md`).
**Contract:** `docs/specs/2026-08-26-t1-type-inference-requirements.md` (the
T1 spec). Settled decisions live there and in
`docs/specs/2026-08-26-t1-derivation.md`; this plan does not re-argue them.
**Baseline:** branch `phase5-capstone`, HEAD `d9515cc9`. Every `file:line`
below was re-verified at this HEAD by the plan author or is carried from the
verification doc (which verified at the same HEAD) — anything neither could
confirm is marked UNVERIFIED.

---

## 1. The target, and the gap from HEAD

The spec's architecture:

    Loader > T1 > Optimizers > T2 > Optimizers > Scheduler

with T1 a class — `Chalk::IR::Transform::TypeInference->new(...)->run($graph)
-> $graph` — that narrows a partially-typed graph until no Value node leaves
stamped `Unknown`, reaching the whole program through EDGES (a Call's MOP
handle), never through a `Map<String,Graph>` passed alongside.

What exists at HEAD, as the verification established it:

1. **A pipeline exists, FUSED INSIDE THE LOADER.** `Serialize/JSON.pm:707`
   calls `Chalk::IR::Analysis->run` and is that method's only caller
   repo-wide. The comment at `:701-706` already states the goal: *"from_json
   should not call this at all… The call stays only so the ~40 existing
   callers keep working during the transition."* So the job is not "assemble
   scattered stages" — it is to create a seam OUTSIDE `from_json` so the
   fused Loader+Analysis can be split, then split it.
2. **The inter-unit edge already exists for direct dispatch.**
   `Node/Call.pm:35` declares `field $target :param :reader = undef;`; two
   writers populate it; `Analysis.pm:597` traverses it
   (`$node->target->graph`). What is missing: the edge exists for only ~15%
   of programs (the classes guard at `Analysis.pm:197`), method dispatch
   still resolves by class-name string (`Analysis.pm:1626-1642`), and no
   Graph carries the MOP (`Graph.pm`: zero mop references — verified).

The remaining gap, item by item:

| Spec section | Missing at HEAD |
|---|---|
| §2 entry contract | No `Chalk::IR::Transform::*` exists. `Analysis::run` is `($class, $graphs, $classes)` → `(\%graphs, $mop)` (`Analysis.pm:183`, `:302`) |
| §6 MOP on the IR | MOP built only when classes exist (`:197`); Graph has no mop field; `to_json` (`JSON.pm:430`) does not round-trip it |
| §7 pipeline object | FIVE inline assemblers, not three: ProgramRunner.pm:199, Mode2Adapter.pm:159, Phase5LibCoverage.pm:71, **son-corpus-wide.t:78 (the gate itself)**, son-e2e.t:66-101 — with load-bearing differences (`program_mode` passed by exactly 2 of 5; three distinct producer filter policies) |
| §10 absorb | `_join_repr` (`Analysis.pm:1004-1026`) drops `Unknown` arms and returns `undef` for siblings; `join_types` has zero callers in `lib/` |
| §4 exit condition | `_assert_value_nodes_are_typed` commented out at `Analysis.pm:298`; enabling it drops the gate 218 → 200 per its own comment block |
| §5 Pi refinement | No Pi node exists; `defined $x` has NO expressible piStamp in the current lattice (B6, confirmed by execution: `meet(Scalar,Scalar)=Scalar`) |
| §8 loader inference | `%LOWERABLE_STAMP` live at `JSON.pm:71`/`:634`; Print→Boolean seed still in the loader |
| §1 no guessing | **CLOSED 2026-08-27 by `e59121b8`** — all four converted to loud GAP dies, pinned by `t/bootstrap/ir/llvm-undef-repr-guard.t` (13/13). The census found all four REACHED but never with an undef left operand: latent hazards, not live miscompiles. Verified independently at G4: zero `// 'Int'` remain in `Context.pm`. |

---

## 2. Blocker dispositions

This plan decomposes around **what must be true before T1 can exist**, in
dependency order, with a decision phase in front; it keeps the old
ordering's dependency DIRECTION (4c→4d→4a→4b→4e) and changes the units.
How the six blockers are disposed of:

| Blocker | Disposition |
|---|---|
| B1 graph-set shape | Resolved by construction: Phase 1 step 7 ships `transforms => [$g -> $g]`; Phase 5 births T1 with `run($graph)`; the transitional hash is fenced (Phase 5, "the fence") |
| B2 Undef-drop vs the 218 floor | RULED (D2): deletion is IN SCOPE (Phase 3 step 4); gate 218 → 215 with three declared GAPs; spec §9.5 amended in the same commit; restoration is T2's acceptance criterion |
| B3 fixpoint freezing + second `_element_repr` caller | Discharged by a mandatory measurement gate (G5) BEFORE the total-join lands; the remedy is chosen from that data (Phase 3 step 0) |
| B4 `$repr // 'Int'` | **CLOSED `e59121b8` (2026-08-27)**, ahead of Phase 3 step 5. Do not re-audit. |
| B5 DefinedOrFold store-blindness | Resolved by construction: the `_element_at` refusal lands in the SAME COMMIT as store-aware `_element_repr` (Phase 4 step 1), with `lli == perl == 99` as the acceptance test |
| B6 inexpressible piStamp | RULED (D1) before any join pin lands: separate refinement vocabulary, `%PARENT` untouched |

---

## 3. Phase 0 — decisions before code

No code. All six are decided; D1 and D2 were ruled by perigrin 2026-08-26
(G0 satisfied).

**D1 — piStamp vocabulary (resolves B6/C3). RULED BY PERIGRIN 2026-08-26:
a separate refinement vocabulary; `%PARENT` is NOT reparented.** Background:
`TypeLibrary.pm:17-56` places `Undef` as a SIBLING of `Str`/`Num`/`Ref`
under `Scalar`; there is no complement operator; `meet(Scalar,Scalar) =
Scalar`, so the spec §5 worked example (`if (defined $x)`) has no
expressible piStamp today. The rule: `piStamp` values are a small closed
set (initially just `NotUndef`) with their own
`refine($pi_stamp, $lattice_type)` meet, defined beside `meet_types` in
TypeLibrary. Phase 3 may pin join results — including
`Boolean,Int -> Str` — against the lattice as it stands today.

**D2 — the Undef drop IS DELETED; the gate drops 218 → 215 (resolves B2).
RULED BY PERIGRIN 2026-08-26: the temporary drop is acceptable; deletion is
IN SCOPE for Phase 3 (step 4).** Deleting `Analysis.pm:1228-1241` moves
L3b/L3c/L3d GREEN → GAP because `Scalar` has no machine encoding until T2
exists (`Context.pm:3646-3651`, `:3676-3682` — dies). Consequences, which
the builder must honour:

- **Spec §9.5's floor becomes 215** for the duration, with L3b/L3c/L3d
  DECLARED GAPs naming `Scalar` and pointing at T2. Amend §9.5 in the same
  commit as the deletion — an unamended spec and a 215 gate is drift.
- **215 is a CEILING as well as a floor while it stands.** A fourth case going
  GAP is a regression, not more of the same; the three are named so a fourth
  is visible.
- **The restoration is T2's acceptance criterion, not a wish.** File it as
  blocked-by-T2: "restore L3b/L3c/L3d to GREEN; gate returns to 218." T2 is
  not done while the gate reads 215.

**D3 — the backend guesses become GAPs (resolves B4).** DECIDED IN-PLAN.
The four `// 'Int'` sites convert to loud dies in Phase 3, after measuring
which corpus cases reach each site. Removing loader compensations makes the
guesses MORE reachable, so they cannot outlive the compensations.

**D4 — the transform contract is `$graph -> $graph`, per graph.** DECIDED
by spec §2. Every seam in this plan threads transforms per graph. A
whole-set hash may survive PRIVATELY inside a module during transition,
fenced — see Phase 5.

**D5 — B5's fix is atomic with the change that exposes it.** DECIDED
IN-PLAN. `DefinedOrFold::_element_at` (`DefinedOrFold.pm:104-135`) learns
to refuse folding for any container with a store-consumer in the same
commit that makes `_element_repr` store-aware. Never split.

**D6 — `program_mode` and producer-filter differences are per-CALL
configuration, never pipeline-object state** (resolves C6). DECIDED
IN-PLAN. Measured: passed by ProgramRunner.pm:207 and son-corpus-wide.t:88;
absent — deliberately, with in-code rationale — from Mode2Adapter,
Phase5LibCoverage, son-e2e.t (Mode2Adapter's `_tag_expected` at `:198`
consumes the `Int:`/`Str:` epilogue that `program_mode` suppresses).
`emitted-ir-is-well-typed.t:108` toggles it per case within one caller.
`lower_opts` rides on `run()`.

---

## 4. Phase 1 — the seam (all five assemblers route through one Pipeline)

**Goal:** one object the harnesses call, so later phases edit ONE site
instead of five (C5: any assembler left inline re-creates the 2026-08-25
218→136 mechanism). Five, not three — the fourth is the gate itself
(`son-corpus-wide.t:60-119`), the fifth is `son-e2e.t:66`.

New file: `t/lib/Chalk/CodeGen/Pipeline.pm` (~120 lines — UNVERIFIED, an
estimate of unwritten code). Under `t/lib` because every caller is
test-tier and `lib/` has zero (verified: no production code calls
`from_json` at all); it moves to `lib/` when a production entry point
exists (§11 deferrals).

Contract, derived from the hardest caller (Phase5LibCoverage wants per-unit
results and does not abort on first failure — `:108-122`):
`run($json, $select, %opts)` returns per-unit result hashes; `%opts` carries
`program_mode` and friends per-call (D6); `transforms => [ sub ($g) {...} ]`
threads PER GRAPH (D4).

Steps (each committed separately; TDD; `$PERL` is
`$HOME/.local/share/pvm/versions/5.42.0/bin/perl`):

1. **The per-unit contract.** RED: new
   `t/bootstrap/codegen-harness/pipeline.t` — build a two-sub program via
   B::SoN, `Pipeline->new->run(...)`, assert an arrayref of 2 unit hashes
   (`label`/`ok`/`ll`/`err`) and that a unit whose lowering dies yields
   `ok => false` without aborting the second. Fails with "Can't locate
   Chalk/CodeGen/Pipeline.pm". GREEN: write the file. The line that reads
   the MOP out of the load result gets a comment naming it as THE single
   site Phase 2 step 4 edits.
2. **Migrate Phase5LibCoverage** (hardest first, so the shape is proven,
   not retrofitted). Baseline the four named diag scalars (`by_stage`,
   `own`, `lowered`, `gap_hist`) BEFORE editing — not a byte-diff of the
   stream (UNVERIFIED that the stream is deterministic;
   `Phase5LibCoverage.pm:61` writes a PID-derived path). Replace `:71` and
   `:108-122`; the unit-selection closure (`:79-98`) stays in the harness
   verbatim.
3. **Migrate ProgramRunner** (the `program_mode => 1` case). Baseline
   `t/bootstrap/corpus/executable-gate.t` first — UNVERIFIED whether it
   emits a scored PASS count; check before relying on it as a signal.
   Replace `:199-210`, preserving the two distinct error strings at
   `:202`/`:204`.
4. **Migrate Mode2Adapter** (the `program_mode`-DELIBERATELY-ABSENT case).
   Baseline `mode2-adapter.t` conformance `{pass,total,pct}`. Replace
   `:159-167`; a comment names WHY `program_mode` is absent (`_tag_expected`
   at `:198` is the oracle) so a future unifier does not helpfully add it.
5. **Migrate son-e2e.t** (`:88-101` — twin of Mode2Adapter: same
   `main::corpus_case` entry, same absent `program_mode`). Live assertions
   at `:224`/`:230` are the check.
6. **Migrate son-corpus-wide.t** `run_through_bson` (`:78-91`). Keep the
   separate-stderr lli capture (`:93-119`) in the test — oracle plumbing,
   not pipeline. **This edits the gate file: gate run G1 follows.**
7. **Prove the seam without building T1.** RED: pipeline.t gains
   `transforms => [ sub ($g) { $seen++; $g } ]`; assert `$seen` equals the
   graph count and lowered output is byte-identical to the no-transform
   run. GREEN: `field $transforms :param = [];` threaded per graph. Two
   lines. This is the whole T1/T2/Optimizers accommodation, and it is born
   in the spec-§2 shape.

**Exit:** G1 gate run (coordinator). Floor 218; `loader-reproduces-the-wire.t`
still reads 16. If any assembler is left inline, STOP — do not enter
Phase 2.

Out of Phase 1's scope: the ~17 other `t/bootstrap/*.t` files doing
`from_json`+`lower` inline for single-purpose unit tests (UNVERIFIED
classification for ~13 of them — verifier spot-checked three). They are not
assemblers of the full sequence; they migrate, if at all, in Phase 5.

---

## 5. Phase 2 — the edge exists everywhere (the MOP rides on the IR)

**Goal:** spec §6. The riskiest step
was already proven gate-neutral by the verifier's scratch experiment
(byte-identical stamps on all 218; byte-identical LLVM IR on the
class-less probe). Steps, in order:

0. **Pin the edge that exists; establish RED against the real blocker.**
   New `t/bootstrap/mop/mop-rides-on-the-graph.t` subtest 1: load a
   class-less program in list context, assert the second return value is
   defined. RED today (producer emits `classes: undef`; `:197` skips;
   `JSON.pm:712`'s `wantarray && defined $mop` collapses the list). No
   green — this step only establishes RED. Existing pins stay green:
   `call-target-is-a-metaobject.t` (5/5), `call-node-resolved-handle.t`
   (7/7).
1. **A MOP always exists.** Dissolve the `Analysis.pm:196-222` classes
   guard: `my $classes = (ref … eq 'HASH') ? $data->{classes} : {};`, body
   unguarded; delete `&& defined $mop` from `JSON.pm:712`. Safety argument
   (verifier-corrected): the field-inference passes return 0 on empty
   `$classes` because their WRITE loops are classes-keyed (two of three
   walk every graph first — that is fine); `:238`'s
   `_stamp_method_call_reprs` is already unguarded and already receives
   `{}`. Note `:205`'s `_seed_and_propagate_reprs` newly runs for 186
   cases — covered by the scratch experiment's byte-identical result.
   **Two corrections from recon (2026-08-26), neither a blocker:** the
   argument omits `_attach_call_targets` (`:483-541`), which ALSO newly runs,
   is NOT classes-keyed, and carries a `die` at `:531-537` whose `$cls`
   operand is always truthy because `MOP.pm:29-33` unconditionally seeds class
   `main` (unreachable in the 22 measured cases, but it belongs in the
   argument); and `_stamp_field_access_reprs` returns VOID, not 0 — no
   consequence, its return value is never tested, but "all three return 0" is
   not literally true. **G2 PASSED 2026-08-26 at 218/218/218/218**, coordinator-
   verified on committed HEAD e33ba8ad; nothing was reverted.
   **Gate run G2.** If the gate moves at all, revert — the experiment's
   premise is wrong; do not patch.
2. **Graph carries the MOP.** RED: subtest 3 — every graph's `$g->mop` is
   the same object (refaddr) as the run's MOP. GREEN: `Graph.pm` gains
   `field $mop :param :reader = undef;` + `method set_mop($m)` (a setter is
   REQUIRED — the MOP is sealed after graphs exist; ordering is
   structurally forced, verified: three passes mutate raw `$classes`
   before seal and `MOP/Field.pm` has no type setter). Attach after
   `_replay_classes`. Do NOT assert the invariant on a `to_json`-reloaded
   graph — `to_json` (`JSON.pm:430`) drops it; round-tripping the MOP is
   deferred (§11).
3. **Method dispatch onto the edge** — the step that makes spec §2 true.
   RED: subtest 4 — a `Child->new->m` method-dispatch Call's `target` is a
   `Chalk::MOP::Method`. Fails at `:487-490`'s `eq 'direct'` filter.
   GREEN: widen `_attach_call_targets` to `'method'`, resolving through
   `Chalk::MOP::Class::find_method` (`MOP/Class.pm:143-151` — recursively
   walks `$superclass`; the loader DOES populate it, `Analysis.pm:874-877`,
   and `_classes_in_parent_order` guarantees a parent is declared first).
   **UNVERIFIED RESOLVED 2026-08-26 by recon: the traversal exists.** Do NOT
   use `Chalk::MOP::find_method` (`MOP.pm:67-74`) — it scans `values %classes`
   in unordered hash order and returns the first name match, a
   non-deterministic guess rather than resolution.

   **AMENDED 2026-08-26 — the plan's prescribed GREEN was WRONG and would
   have regressed the gate.** Reading `$node->target->return_type` returns
   `undef` for EVERY method: `MOP::Method` declares
   `field $return_type :param :reader = undef` (`MOP/Method.pm:15`) with NO
   setter, and `_replay_classes` passes ONLY `graph` when declaring a method
   (`Analysis.pm:932-934`) — while `declare_sub` twenty lines below DOES pass
   `return_type`, under a comment explaining precisely why the loader must
   carry the wire's declared type (`:958-966`). **That Method/Sub asymmetry
   is the real defect.** Verified at HEAD by the coordinator; measured live on
   a Base/Child program: `method m return_type=UNDEF` while the corresponding
   Call is correctly `repr=Int`. So step 3 MUST ALSO thread the wire's type
   into `declare_method`, mirroring `declare_sub`:
   `return_type => $wire_rts->{$mname} // 'Unknown'` — `Unknown`, never
   `undef`, for the reason `:958-964` already gives (an absence forces every
   downstream consumer to invent its own meaning). This is real added scope
   the original step did not budget.

   **THE DIE MUST BE RE-SOURCED, NOT MERELY KEPT.** The wire-vs-graph
   disagreement die at `:1598-1605` is load-bearing and stays — but it
   compares the WIRE value (`$wire_rts->{$mname}`, read at `:1584`) against
   the GRAPH-derived value (`$ret->inputs->[0]->representation`). Moving the
   wire value onto `MOP::Method::return_type` re-sources its left operand
   (`$method->return_type`), while the right operand still needs the
   `$graphs->{$methods->{$mname}}` walk that lives in the very loop being
   rewritten. Keeping the die AND rewriting resolution are in tension: if the
   shape is not fixed deliberately, the die is silently weakened into
   comparing a value against itself. **Prove it still fires**: a test that
   forces a wire/graph disagreement and asserts the die, red before and green
   after — otherwise "kept" is unverified.

   **Before landing, settle the OPEN DISAGREEMENT on revert-independence in
   scratch** — RESOLVED 2026-08-26 by recon: step 3 IS independently
   revertible. Step 1's `$classes` is block-lexical (dies at `:221`) while the
   `:237` fixpoint reads `$data->{classes}` directly, and the two changes
   touch DISJOINT node populations (every `classes: undef` case measured has
   zero Call nodes; every method-Call case has populated `classes`, where step
   1 is a proven no-op). **CAVEAT, and it is the important half: because the
   domains are disjoint, a step-3 revert looks clean EVEN IF STEP 3 WAS
   WRONG.** G3's revert check is therefore NOT evidence that step 3 is
   correct — only the method-stamp tests are. **Gate run G3.**

4. **Collapse the return shape.** `Analysis.pm:302` → `return \%graphs;`;
   `JSON.pm:707` single-value; delete the wantarray line at `:712`; fix
   the stale comment at `Analysis.pm:300-301` (false of its own function).
   Then the 27 two-value call sites across 25 files (all under `t/`, zero
   in `lib/` — verified census in the verification doc) become
   `my $graphs = from_json($json); my $mop = (values %$graphs)[0]->mop;`.
   **Hand-re-read the three one-value-LIST silent survivors**
   (`ir-serialize-json.t:238`, `ir/lowerable-stamp-admission.t:47`,
   `ir/loader-reproduces-the-wire.t:123`) — they keep passing through any
   change to the second value and cannot be trusted to fail. This step
   most resembles the 218→136 change; it lands ONLY because Phase 1
   migrated all five assemblers (C5). **Gate run G4.**
**REVIEW DEBT, RULED 2026-08-26.** Steps 0-3 received adversarial VERIFICATION
   (did behaviour change: 22-case differential, 240-case corpus sweep, bidirectional
   die sabotage) but NOT agentic REVIEW (is the code sound). Phase 1 received
   neither — its `Pipeline.pm` is new infrastructure that all five assemblers
   INCLUDING THE GATE route through, so a wrong-but-consistent Pipeline reads as
   green. perigrin ruled: defer, and review Phase 1 + Phase 2 as ONE unit at G4.
   **That review is a G4 exit condition, not optional cleanup.** Evidence the gap
   is real: `LLVM.pm:538`'s latent `// ` bug was found by a step-3 agent tripping
   over it, not by anyone reading the code — and its four B4 siblings are still
   unreviewed with Phase 3 heading straight at them.

5. **Do NOT delete `_build_registry_from_mop`.** It derives six classes of
   fact the MOP does not hold (vtable slots, flattened inheritance,
   exactly-one-Return enforcement, return-repr fallback, `:reader`
   synthesis records, two policy filters — all six re-confirmed). Its
   retirement belongs to the LLVM-reads-MOP work (§11).

---

## 6. Phase 3 — the total join, and the guesses retire

**Goal:** spec §10 (absorb) and §1 (no silent guess), on the join that
every Phase-4 analysis folds over, plus the D2 deletion. Steps 1–3 are
measured corpus-inert; the phase is bracketed by a measurement gate in
front (B3) and a gate run behind with an EXACT expected value.

0. **G5 — discharge B3 before any join code.** Re-run the total-join
   simulation over the corpus, instrumenting: BOTH `_element_repr` callers
   (`Analysis.pm:1170` literal-aggregate path AND `:1510` field-default
   path feeding `%field_elem_type` → the `:1541-1548` Subscript stamping);
   nodes frozen-by-first-`Scalar` across fixpoint iterations (the `:1148`
   guard — `_is_narrowed` at `:448-450` counts `'Scalar'` as narrowed, so
   a first-pass Scalar stamp is PERMANENTLY skipped where HEAD's undef
   would be revisited — widening without a merge requiring it, forbidden
   by spec §3/§9.3); and whether a Scalar-joined return can reach the
   `:1598` die. **Then decide, from the data:** withhold the join result
   until the fixpoint stabilizes, or teach `_is_narrowed` that `Scalar` is
   refinable. Either remedy lands WITH step 2, not after it. The old
   "exactly 3 movers" figure is not usable as a revert criterion — its
   simulation could not see `:1510` or the freezing.

   **DISCHARGED 2026-08-27. Result: NO REMEDY AT STEP 2 — it moves to step 4,
   ratified by perigrin.** Measured over 231 corpus cases with BOTH callers
   instrumented (locate sites by CONTENT: every Phase-3 line number in this
   plan runs ~50 LOW against HEAD): the total fold changes NOTHING. Zero
   movers, not three; zero nodes stamped `Scalar` anywhere; zero freeze
   events; the fixpoint runs the same 2 iterations; the `:1598` die is
   unreachable (its 7 die-eligible methods are structurally join-immune).

   Root cause of the null, which this plan did not know: **the corpus produces
   NO heterogeneous join at all** — 94 `_join_repr` calls, every one
   homogeneous — because the Undef drop and the TernaryExpr condition-drop
   both run AHEAD of the join. A MEASURED null, not a blind one: sensitivity
   controls forcing a `Scalar` produce 228 freeze events, 65 on iteration
   >= 2, so the harness detects the hazard when it is present.

   The hazard is real as a code-reading and has NO INSTANCE until step 4
   deletes the Undef drop and makes `join(Undef,Int) = Scalar` reachable. A
   remedy here would be unexercised code with a green-on-arrival test — the
   defect class this plan refuses elsewhere. **The remedy lands in step 4.**
   If one is needed, the data favours teaching `_is_narrowed` that `Scalar`
   is refinable (13 call sites, one contract, and `Scalar` is by construction
   not a commitment) over restructuring the write discipline.

   **The usable revert criterion for step 2 is ANY nonzero stamp diff**, not a
   movers count. Re-run the harness (`scratchpad/g5/`) as step 4 gate.
1. **Absorb.** RED: rewrite `t/bootstrap/join-drops-unknown.t` →
   `join-absorbs-unknown.t`: `_join_repr('Int','Unknown') eq 'Unknown'`
   and the reverse arm order (both return `'Int'` at HEAD). Keep the
   `Int,Str -> Str` and all-Unknown anchors. Rewrite the file's rationale
   comment (it argues FOR drop) and its stale `JSON.pm:1548` cross-ref.
   GREEN: delete `Analysis.pm:1007-1018`. Record in the commit that absorb
   is INERT until `%LOWERABLE_STAMP` admits `Unknown` (spec §8) — the
   filter nulls every Unknown wire stamp before inference, so
   drop-vs-absorb disagreement is 0 today (mechanism verified; exact
   census UNVERIFIED).
2. **The total fold.** RED: new unit test pinning
   `('Undef','Int') -> 'Scalar'`, `('ArrayRef','Int') -> 'Scalar'`,
   `('Array','Int') -> 'List'`, `('Boolean','Int') -> 'Str'` (pin this one
   with a comment: perigrin RULED `Boolean <: Str` intended — a later
   reader must not "fix" the lattice), `('Slot','Int') -> 'Unknown'`,
   `('Slot','Slot') -> 'Slot'` (the `TypeLibrary.pm:301` equal-shortcut
   fires before absorption), `('Slot','Unknown') -> 'Unknown'`. All RED at
   HEAD (undef or drop). GREEN: `_join_repr`'s body (`:1004-1026`) becomes
   a fold of `TypeLibrary::join_types`; keep the empty-list `return undef`.
   Bundle the G5 remedy. Preserve `Analysis.pm:1214` (the TernaryExpr
   condition-drop) — it alone keeps `ternary-joins-arms-only.t` subtest 1
   green (`join_types('Boolean','Int','Int') = 'Str'` over the raw list).
   Verify: simulation still shows ZERO stamp changes (the Undef drop at
   `:1240` still runs ahead of the join at this step; it is deleted in
   step 4).
3. **Delete the dead `'same'` branch** (`:1218-1226`; `:1192` becomes
   `if ($rule ne 'join')`). Dead since 6d9fc083 — `%_COMPUTED_REPR` maps
   And/Or to `'join'`; nothing maps to `'same'`. No red test can exist for
   unreachable code; the honest check is a coverage assertion that no
   `%_COMPUTED_REPR` value is `'same'`. **Commit separately** so any gate
   movement is attributable.
4. **The Undef drop is deleted (D2).** Delete `Analysis.pm:1228-1241`.
   Same commit: amend spec §9.5's floor to 215 with L3b/L3c/L3d as
   DECLARED GAPs naming `Scalar` and pointing at T2; update the three
   corpus contracts (`logical.md:180`, `logical.md:1053`, L3c's
   Region-Phi) per the verification doc's parked-step-4 procedure; lower
   the gate floor assertion (`son-corpus-wide.t:322`) to 215. File the
   restoration on zhi (D2, §11). **Commit separately; expected gate: 215
   EXACTLY** — any other number falsifies the D2 accounting.

   **LANDED 2026-08-27. Deletion + spec amendment + the three corpus
   contracts + the gate floor, in one commit as D2 requires.** Located by
   content, not by number (the plan's `:1228-1241` is `:1261-1274` at HEAD).

   **The D2 accounting is CONFIRMED BY MEASUREMENT, not just arithmetic.**
   Full node-by-node stamp diff over all 231 corpus cases, drop-present vs
   drop-deleted: **2971 stamps each side, 5 nodes differ, in exactly 3 cases**
   — L3b `DefinedOr` Int→Scalar, L3c `Phi#6` Int→Scalar, L3d `DefinedOr`
   Int→Scalar, plus the two Coerce nodes whose `from=` identity follows. The
   corpus-wide untyped-node count is UNCHANGED (812 both sides): nothing else
   went untyped. 218 − 3 = 215.

   **B3 REMEDY: REFUSED, on positive evidence.** The hazard went live exactly
   as G5 predicted — 0 `Scalar` guard-skips before the deletion, **9 after
   (3 on iteration ≥ 2)**. But all three candidate landings are net-negative:

   1. **The plan's favoured remedy DOES NOT TERMINATE.** Teaching
      `_is_narrowed` that `Scalar` is refinable diverges: L3b alone reached
      iteration **457,642** and was still climbing when killed (237MB log vs
      1.3MB normal). Mechanism, confirmed by reading: **all six `$changed = 1`
      sites in `_propagate_computed_reprs` are UNCONDITIONAL** — none tests
      whether the repr actually moved. Loop termination rests ENTIRELY on
      `_is_narrowed` acting as a one-shot latch. **This inverts the plan's
      cost comparison:** `teach_is_narrowed_scalar_refinable` cannot be landed
      alone at all; it REQUIRES `withhold_until_fixpoint_stable` (the option
      the plan deprioritised as "a larger diff for the same effect") as a
      prerequisite, because the latch it removes is what makes the loop finite.
   2. **With termination restored, the freeze withholds NOTHING.** Probe =
      Scalar-refinable + idempotent join write (`next if $prev eq $widest`);
      terminates, max iteration 2. Every node's FINAL repr is identical to the
      frozen run. The hazard's premise — "a later refinement is permanently
      lost" — is measured FALSE here: a merge's join is computed from arms that
      are already final, so there is no better second answer being suppressed.
   3. **Its only measured effect is a regression.** The 4 differing lines are
      two Coerce nodes' hash-consed identity: frozen records
      `Coerce|from=Scalar`, unfrozen records `Coerce|from=Unknown` — the Coerce
      is built from a STALER reading of its still-moving input.

   So the remedy is refused for the same reason step 2 refused it, but now on
   evidence rather than absence. **Revival trigger:** some pass must be able to
   narrow a node AFTER it is first stamped `Scalar`; nothing does today. The
   precondition for any future remedy is the write-discipline fix (`$changed`
   only on an actual move) — that is the load-bearing half and `_is_narrowed`
   is the cosmetic half. **Do not land them in the other order.** Data:
   `scratchpad/g5/NOTES.md`, "G5 RE-RUN at step 4".
5. **The guesses become GAPs (B4, D3).**

   **CENSUS DONE 2026-08-27: NO LIVE GUESS. The "report before converting"
   trigger did NOT fire; step 5 is gate-inert.** All four sites ARE reached
   (`:3349` x2 cases, `:4071` x1, `:5801` x2, `:6827` x11) but the left
   operand is ALWAYS DEFINED, so the fallback never supplies a value. Verified
   with a POSITIVE CONTROL rather than a bare zero: undef-only warns reported
   nothing, then the same warns made unconditional lit up all four — so the
   zero is a true negative, not dead instrumentation.

   **The reaching values are NOT uniformly `Int`.** `:6827` sees `Str`
   (Child.kind, Animal.name, Greeter.hello) and `Undef` (Counter.bump). These
   sites are safe because the operand is always DEFINED, not because `Int`
   was the right guess — had a `Str` case arrived undef, the guess would have
   emitted an i64 ABI cast over a string, exactly the silent-garbage channel
   spec §1 forbids. Converting costs nothing at the gate today and closes the
   channel against a future producer.

   Conversion notes from the census: `:5801` is already effectively dead (the
   next line dies unless repr eq `Int`), so dropping its `// 'Int'` is a
   simplification rather than a new guard; `:3349` uses `$repr` TWICE in one
   ternary, so hoist ONE required-repr fetch above the expression or the die
   cannot say which read failed.

   Original instruction, for reference: First MEASURE which corpus cases
   reach each of `Context.pm:3349`, `:4071`, `:5801`, `:6827` (an
   `warn`+run over the corpus in scratch — not committed). Then RED: a
   unit test per site driving a repr-less node into it, asserting a die
   whose message names the node and the missing repr (GAP shape, not
   `Int`). GREEN: `// 'Int'` → `// die "GAP: ..."`. `:3349` is on the
   DefinedOr phi path — if the measurement shows corpus cases reaching a
   site with a live guess, THAT IS A LATENT MISCOMPILE at HEAD; report it
   to perigrin before converting, since conversion will move the gate
   (GREEN → GAP is a gate drop treated as a finding, not a regression).
6. **Exit: G6 gate run.** Expected 215 exactly (218 minus the three D2
   GAPs; steps 1–3 are corpus-inert). Exception: if step 5's measurement
   found live-guess cases, subtract those too — each is a loud GAP naming
   a real bug; perigrin decides between landing that and reverting the
   specific site pending a fix.

---

## 7. Phase 4 — the analyses read edges (and only edges)

**Goal:** the whole-program analyses gather their fact sets by traversal,
so T1's one-graph contract is real. Re-scoped per C2: the fold belongs to
Phase 3, the guard hoist to Phase 2; what remains:

1. **Container monomorphism + B5, atomically (D5).** RED (two tests):
   `t/bootstrap/ir/element-repr-joins-stores.t` — load
   `my @arr=(1,2); $arr[0]="hello"; print $arr[0];`, assert the
   post-store Subscript's stamp is `'Str'` (verified `Int` at HEAD, with a
   wrong `Coerce(Int->Str)` in front); and the B5 probe
   `my @arr=(1,2); $arr[0]=99; my $v=$arr[0]//5;` asserting
   `lli == perl == 99` (HEAD folds to the initializer `1`). GREEN:
   `_element_repr` (`:1315`) gathers initializers ∪ every store's rhs by
   walking consumer edges (container → Subscript consumers → each lvalue
   Subscript's Assign; consumer edges verified populated through
   `NodeFactory::_register_consumers`), joins with the Phase-3 fold; AND
   `_element_at` refuses to fold any container with a store-consumer.
   Same commit. Check the `:1510` field-default caller explicitly — its
   lifetime assumptions differ. Verify `ir/son-aggregate-repr.t`,
   `ir/llvm-aggregate-latent-fixes.t` (its `:539` TODO is this exact
   path), and by hand: the `Context.pm:2547` GAP no longer fires for the
   Str-store case and lli prints `hello`. Do not relax the `:2543`
   repr-guard until the join demonstrably reports the widened type.
2. **`_resolve_direct_calls` reads the edge.** RED:
   `resolve-direct-calls-reads-the-edge.t` — perturb the graph-name hash
   (callee bound under a different key); only the edge survives. Fails at
   `:545`'s `$graphs->{$node->name}`. GREEN: `$node->target->graph`
   (verified same object by refaddr — assert that IN the test before
   removing the hash read). `loader-reproduces-the-wire.t` must stay at
   16, not rise.
3. **G7, then argument seeding joins ALL callsites.** First MEASURE the
   UNVERIFIED claim "only 4 callees-with-multiple-callsites, zero
   polymorphic, so the gate cannot validate this change" — it is the
   entire justification for the step's test strategy and has no recorded
   evidence. Then RED, bilateral per CLAUDE.md and per the verifier's
   proof that one direction alone is vacuous:
   `sub g { my $x = shift; return $x } my $a = g(1); my $b = g("hello");`
   asserts the shift-read stamps the JOIN (`Str`), and each Call is NOT
   stamped from the other site's argument alone — in BOTH call orders
   (reversed order stamps both `Int` at HEAD: a Str value carrying an Int
   stamp, the dangerous direction). GREEN: restructure
   `_seed_direct_call_arg_reprs` (`:582-672`, both first-caller-wins
   guards `:~626` and `:~666`) into gather-then-stamp: bucket direct Calls
   by `refaddr($node->target)` in one forward sweep (no back-edge needed —
   the callee is a shared singleton, verified), join per argument
   position, stamp once; guards become "stamp only if the joined value
   differs", preserving fixpoint termination; keep the `:247-250` outer
   fixpoint. Verify the three white-box internal callers
   (`ternary-joins-arms-only.t:39`,
   `typelibrary-is-the-coercion-authority.t:67`, `:99`) — they call pass
   internals directly and break on signature changes — and
   `ir/stamp-alias-preconditions.t` (an active enforcement sweep over all
   of `lib/`; it constrains where new type-axis readers may live).
4. **The no-tie assertion.** RED-proof first: point the grep test at a
   fixture containing `tie my @a, 'Foo';` and watch it fail; then land
   `t/bootstrap/no-tie-in-the-subset.t` green over `lib/` (operator-form
   patterns; both repos re-measured at zero). No IR pass — the analysis
   does not need to exist; the obligation is a guard on the source subset.
**G7 DISCHARGED 2026-08-27, and it REFUTED this step's own bilateral
   prescription.** Census over 231 cases: **4 multi-callsite callees, ZERO
   polymorphic** (confirmed twice — by IR census keyed on
   `refaddr(target->graph)`, and by an independent source-text count). So on
   every gate case `join(args) == args[0]`, and gather-then-stamp is
   behaviourally IDENTICAL to first-caller-wins: **the gate holds whether the
   join is correct, inverted, or absent.** The tests carry the whole burden;
   G8 green says nothing about the join.

   The plan said to get bilaterality by REVERSING THE CALL ORDER. Measured,
   that is vacuous: both orders stamp `Int` identically, because
   first-caller-wins is first in `Graph::nodes()` TOPOLOGICAL walk order, not
   source order, and content-derived node ids merely swap which id carries the
   Int. One assertion written twice. The real bilateral pair is
   TYPE-DIRECTION: **widening lost** (shared read stamped Int while a Str
   reaches it) and **narrowing invented** (a Call stamped from its sibling
   site alone). The landed test
   (`ir/direct-call-args-join-all-callsites.t`) asserts both plus explicit
   ORDER-INDEPENDENCE, since monomorphic seeding is correct today only by
   accident of a walk order MEMORY warns against changing.

5. **Exit: G8 gate run.** Floor 215; expected movement: cases that
   previously GAPped at `Context.pm:2547` on heterogeneous stores may go
   green — a floor RAISE, taken only on a run where the gate holds
   (spec §9.3 pairing rule).

---

## 8. Phase 5 PREFACE

### 5.0 - `%LOWERABLE_STAMP` IS AT THE WRONG LEVEL (perigrin, 2026-08-27)

**This is a LEVEL VIOLATION and it is the root cause of most of Phase 5's
trouble.** `%LOWERABLE_STAMP` (`Serialize/JSON.pm:72-73`) asks *can the BACKEND
encode this?* - a T2-axis question - and runs inside `from_json`, the LOADER,
three phases upstream. Its own comment convicts it: every sentence is about
machine encodings (`%Array*` as `{i64, i64, %Slot*}`, "for want of a boxed value
representation"). That is `Target::LLVM` reasoning living in the deserializer,
and the name says it out loud: **LOWERABLE**.

Same class as the `$repr // 'Int'` guesses Phase 3 retired: the backend's
encoding question answered without the authority to answer it. Four small
instances fixed; the large one left standing.

The symptom list is one cause:

- **233 wire `Unknown`s written into the graph as ABSENCES** (231 cases
  measured) - the absent/Unknown conflation spec 4 forbids, committed by the
  loader before T1 exists.
- **T1's frontend metric corrupted**: post-load "absent = 23" is residue of 233
  dropped `Unknown`s, not 23 frontend bugs.
- **Absorb inert** - Phase 3 step 1 had to record that `join(Unknown,T)` changes
  nothing, because the filter nulls every Unknown before inference sees it.
- **G5's null** - no heterogeneous join in the corpus, 94 calls all homogeneous.
- **The circularity in old step 5** - the filter is deletable once
  Unknown-at-exit is zero, but the filter is what makes Unknown unmeasurable.

**CORRECTION 2026-08-27: THE BOUNDARY IS ALREADY BUILT. §5.0 is ONE half, not
two.** An earlier note here (and a message to the bson session) claimed §5.0
also had to teach the backend boundary to refuse `Unknown`, on the grounds that
`_require_repr` (`Target/LLVM.pm:80`) checks only `undef`. **That was wrong:
`_require_repr` is not the boundary.** The boundary is
`Context.pm:_repr_to_llvm_type` (`:3679`), it is the ONLY path from a
representation to a machine type (8 call sites, zero bypasses — the one
non-funnel mapping at `:2100` is a `Coerce` arm whose target is already known),
and it is TOTAL by construction: known type, or `%_REPR_NO_MACHINE_TYPE` with a
reason, or "not a representation this compiler knows at all — a new repr
reaching here needs a decision, not a default."

Verified by execution: `Int -> i64`, `Str -> %Str`, and `Scalar`, `Unknown`,
`List`, `undef` each die with a DISTINCT message. The table already draws the
distinction this section is about, in its own words: *"NOT the same as Unknown:
Scalar is a legitimate static answer, Unknown is an inference failure."*

So removing the loader filter cannot produce a silent garbage encode. It
produces a loud GAP naming the node — which is the outcome §5.0 wanted, already
implemented, waiting for the filter to stop hiding the cases from it.

**THE FIX - move the QUESTION, keep the ANSWER.** Loader reproduces the wire
verbatim (spec 2); T1 narrows and can finally SEE `Unknown` as the input value
spec 3 says it is; T2's boundary answers encodability and refuses an
un-encodable type LOUDLY. What the loader dropped silently, the boundary GAPs -
GAP-not-miscompile preserved by construction.

**MEASURED 2026-08-27, wire cache at producer `a8685ba`, 240 corpus wires.**
What the loader drops, counted over every stamped node in every graph of every
wire (so these totals include producer internals pulled in by `use`; the
PROPORTION is the finding, not the absolute):

| stamp | dropped | what it is |
|---|---|---|
| `Unknown` | 208,660 | the lattice top — the known case |
| `Scalar` | 1,683 | top of the SCALAR SPINE — a legitimate answer, discarded |
| `List` | 720 | signature vocabulary |
| `ScalarRef` | 480 | **not a representation the backend knows AT ALL** |
| `Regex` | 1 | compile-time only |

**211,544 of 437,109 stamped nodes — 48% — never reach the graph.**

Two things this changes about §5.0's framing:

1. **The filter is not just hiding `Unknown`.** It discards FOUR kinds of real
   type information, three unrelated to inference failure. `Scalar` in
   particular is a legitimate static answer (top of the spine, encoding `%Slot`
   once T2 exists) and the loader throws it away.
2. **`ScalarRef` is an unanswered DESIGN QUESTION, not noise.** The producer
   emits it 480 times; `_repr_to_llvm_type` routes it to the
   *"not a known representation"* fallthrough, whose own comment says "a new
   repr reaching here needs a decision, not a default." So deleting the filter
   surfaces a decision nobody has made — which is the right outcome (a loud
   refusal beats a silent drop), but it must be EXPECTED rather than read as
   §5.0 breaking something.

**AND THE FILTER MAKES THE BACKEND BLAME THE WRONG LAYER.** Measured on the
same cache, the correspondence is exact. The ops the wire stamps `Unknown` are

| op | wire says `Unknown` |
|---|---|
| `Call` | 66,277 |
| `PadAccess` | 46,570 |
| `Subscript` | 35,778 |
| `Assign` | 17,523 |
| `FieldAccess` | 9,366 |
| `EntryDef` | 5,040 |

and the backend's top refusals on the same corpus are `PadAccess`,
`Call(method)`, `Defined.operand`, `Subscript.container`, `Assign`, `EntryDef`
— all of them *"reached LLVM backend with NO representation (undef) — **fix
TypeInference** so this node carries an explicit repr before lowering."*

The chain, measured end to end: the producer stamps `Unknown` (an honest
answer); the loader DELETES it because `%LOWERABLE_STAMP` omits `Unknown`,
leaving the field absent; the backend then refuses and **names TypeInference as
the culprit**. But inference never saw a value to narrow — the loader removed it
first.

So the level violation does not merely corrupt a metric. **It produces a
MISLEADING DIAGNOSTIC**, which is worse than a redundant one: it sends the next
reader to debug T1 for a defect in `Serialize/JSON.pm`. Deleting the filter
fixes the message as a side effect, because an `Unknown` that arrives intact
gets the accurate refusal ("this value may be anything… the program cannot be
compiled until something NARROWS it") instead of a false accusation.

**AND IT IS NOT A ONE-LINE EDIT: THE FILTER IS ALSO A PERFORMANCE GUARD.**
Measured 2026-08-27 on the A/B trees (wire cache `a8685ba`, live `lib/`
untouched), loading ONE wire — `arithmetic-1.json`, 412 graphs:

| tree | `from_json` |
|---|---|
| filter intact | **5.93s** |
| filter removed | **>900s (capped, never completed)** |

**>150x, and it is in the LOAD, not in lowering.** A full corpus arm ran 338
minutes of CPU against ~25 for the baseline before being killed.

The mechanism follows from Phase 3's finding that `_is_narrowed` is the
fixpoint's TERMINATION LATCH. Today ~48% of stamps are deleted at load, so those
nodes are ABSENT and do not re-enter the loop the same way. Admit all 208,660
`Unknown` stamps and every one becomes a node the fixpoint keeps revisiting,
because `Unknown` is not narrowed. The filter has been accidentally acting as a
throughput guard on an inference loop never designed for the full `Unknown`
population.

**Consequence for sequencing.** §5.0 cannot be "delete the filter and measure":
that is a one-line edit whose cost is a compiler that does not finish. The
filter comes out only once the fixpoint tolerates `Unknown` at scale — which is
T1's job (a worklist that does not re-derive a node whose inputs have not
changed), not the loader's. **§5.0 therefore lands AFTER T1 exists, not before
it.** The earlier "5.0 lands BEFORE the MOP graph registry and before T1" is
retracted; what still holds is that T1 must be built against numbers this filter
distorts, so the MEASUREMENT above is the input to T1's design rather than a
prerequisite edit.

**5.0 lands BEFORE the MOP graph registry and before T1** - both were being
built against numbers this filter distorts. Measure the blast radius first
(scratch A/B, CWD inside the scratch tree); the filter has been load-bearing a
long time and `Unknown` reaching the backend is exactly what it prevented.

### 5.0b - THE UPSTREAM QUESTION: why does the wire carry `Unknown` AT ALL?

perigrin, 2026-08-27, and it cuts deeper than 5.0. 5.0 moves a filter
downstream; this asks why the input needs filtering. **233 `Unknown` stamps on
the wire is a FRONTEND defect, not a fact of life.** B::SoN walks a real optree
with real SV types available; nothing the Chalk backend does with those types
could not have been determined at the producer. An `Unknown` on the wire is the
producer declining to answer a question it was holding the evidence for.

Filed as its own workstream (separate session, perl5-son): audit what the 233
actually are, by op and by cause, and close the ones the optree can answer. The
two are complementary - 5.0 makes chalk honest about what it receives; 5.0b
reduces what there is to be honest about. **Neither blocks the other**, and
5.0's GAP-shaped refusal is what makes 5.0b's remaining cases visible instead
of silently dropped.

**BELT AND SUSPENDERS, deliberately** (perigrin): they fail in different
directions and neither alone is sufficient. Fix only the producer and chalk
still TRUSTS its input, so the next producer regression silently drops stamps
again - the defect class that produced this whole phase. Fix only the boundary
and the 233 real `Unknown`s become loud GAPs: honest, but not compiling. Both
gives the producer answering what it can, and the boundary refusing what it
cannot rather than guessing.

## 8. Phase 5 — T1 is born, and the loader stops analysing

**Goal:** after phases 1–4 the seam exists, the edge is total, the join is
total, the analyses traverse edges. Now the class exists and the fusion
ends.

1. **The class, with the spec-§2 contract.** RED: new
   `t/bootstrap/transform/type-inference-contract.t` — 
   `Chalk::IR::Transform::TypeInference->new->run($graph)` returns a
   graph; a Value node arriving stamp-less is `Unknown` after entry
   normalization (spec §4); control nodes are untouched. GREEN: new
   `lib/Chalk/IR/Transform/TypeInference.pm` whose body DELEGATES to the
   existing `Analysis` sequence. **AMENDED 2026-08-27 — the original fence was UNBUILDABLE; measured, not
   argued.** It said the transform reaches the program via `$graph->mop`,
   which 'enumerates the compilation unit's graphs'. **The MOP cannot do
   that.** `Chalk::MOP` holds only `%classes`; a graph is reachable solely
   as `MOP::Method->graph`, `MOP::Sub->graph`, or a field default. Measured
   on a real wire (coordinator-reproduced): of Point::__DEFAULT_0,
   Point::bump, Point::x, main::__PROGRAM__, main::helper, only **bump and
   helper are REACHABLE** — the entry graph `main::__PROGRAM__`, the
   `:reader` accessor, and the field default are NOT. On a class-less
   program it is 0 of 1. Enumerating that way hands the passes a SILENT
   SUBSET that omits the very graph the corpus gate lowers: spec §1's
   **guess** row, not its GAP row.

   Second, independent leg — an ORDERING one no better registry fixes: step 4
   makes `from_json` return decoded graphs and nothing else, but
   `Graph::$mop` is populated ONLY by the `set_mop` sweep inside
   `Analysis`. Once Analysis leaves the loader, every graph arrives at T1
   with `mop => undef` — so `$graph->mop` is undef AT T1'S ENTRY BY
   CONSTRUCTION.

   **RULED BY PERIGRIN 2026-08-27: give the MOP a unit-level GRAPH REGISTRY**,
   populated where the `set_mop` sweep already runs, and attached by the
   LOADER so it survives the split. The MOP becomes the honest unit handle it
   was always described as; `$graph->mop` stays the single edge; spec §2's
   real prohibition — no `Map<String,Graph>` in a PUBLIC signature, no
   `$classes` parameter — is satisfied, since the registry is reached
   THROUGH the edge rather than passed alongside it. Note what this does NOT
   change: the `%graphs` hash the existing passes still take stays PRIVATE to
   `Analysis.pm`, with its elimination the filed migration in §11.

   No `$classes` parameter anywhere public.
2. **Entry normalization and the frontend metric.** RED: a wire with a
   stamp-less Value node yields (a) that node stamped `Unknown` post-entry
   and (b) an arrived-absent count of 1 in T1's report — reported
   WHETHER OR NOT T1 later types it (spec §4). Baseline: absent + Unknown
   = 11 + 0 = ELEVEN across the corpus (the verifier's corrected metric;
   the measurement's "already zero" split absent from Unknown exactly as
   spec §4 forbids).
3. **The exit REPORT (spec §9.4).** RED: T1's result carries
   `{unknown_at_exit, arrived_absent, narrowed_count, widened_without_merge}`;
   the report is asserted present, its numbers are asserted against the
   known baseline (18 cases fail the exit condition today per
   `Analysis.pm:314`'s own comment). NOT an assertion that must be
   disabled — that is what `_assert_value_nodes_are_typed` (`:298`,
   already commented out) already is. The five well-typed conditions
   (old plan §"What well-typed means") are checked by running
   `TypedInvariant` over stamps as part of the report; care point:
   `%OP_REQUIRES_OWN_REPR` (Add/Subtract/Multiply) is node-relative
   exactness and is load-bearing — do not relax it (the `eq`→`is_subtype`
   conversion was tried and killed; the old plan's slice-5 analysis of
   WHY stands and is incorporated here by reference).
4. **The split.** Move the `Analysis->run` call out of `from_json`
   (`JSON.pm:707-712` deleted; `from_json` returns decoded graphs and
   nothing else) and into the Pipeline's transforms slot as T1. The ~34
   `t/bootstrap` unit-test callers that got inference for free take a
   test-tier helper (`t/lib`) that runs load-then-T1 — count UNVERIFIED
   at this HEAD; re-derive with
   `grep -rln from_json t/bootstrap --include='*.t'` before executing.
   **Acceptance, the two numbers that must move together (spec §7/§9.1):**
   `loader-reproduces-the-wire.t` reads **0** and asserts, AND the gate
   holds at **215** (D2's number until T2). One change does both or the
   seam is wrong.
   **Gate run G9.**
5. **What does NOT happen here:** `%LOWERABLE_STAMP` and the
   Print→Boolean seed stay in place until the exit report's `Unknown`
   count reaches zero (spec §8: the filter is deletable on T1's
   COMPLETION — while Unknowns still leave T1, the filter is what keeps
   the poison value out of the shared stamp/representation field, per the
   old plan's 3b record). Tracked in §11.

---

## 9. Phase 6 — Pi flow refinement

**Goal:** spec §5. Last because nothing else depends on it and it is the
only cross-repo phase (88 = 88 node-class parity; consumer-first is the
only safe order). D1's vocabulary decision was made in Phase 0; this phase
implements it.

1. **The vocabulary (D1 implementation).** RED:
   `t/bootstrap/ir/pi-stamp-vocabulary.t` — the fact proved by
   `defined $x` on a `Scalar` input is expressible and strictly narrower
   than `Scalar`. Cannot pass at HEAD. GREEN: the separate refinement
   vocabulary with its own meet, `%PARENT` untouched. `meet_types` is NOT
   exported (verified — TypeLibrary has no EXPORT lists); call
   fully-qualified or add the export deliberately.
2. **The node, Chalk side.** RED: `pi-node.t` — factory-built Pi;
   `operation eq 'Pi'`; two Pis over the same input at DIFFERENT guards
   are distinct nodes; `effective_stamp == refine(pi_stamp, input.stamp)`.
   GREEN: `lib/Chalk/IR/Node/Pi.pm` — `:isa(Chalk::IR::Value)` (the
   Value predicate is closed on that class), `identity_kind 'per_call'`
   (hash-consing same-piStamp Pis would merge refinements from different
   guards — the C2 bug spec §5 row 3 names), registered in
   `NodeFactory.pm:91`'s `%DATA_CLASSES`. Confirm Pi lands in
   `node-identity-kind.t`'s `@checked`, not silently in `@unbuildable`
   (needs a `%REQUIRED` entry at `:144`).
3. **Topo order, red status unknown.** (The old TypedInvariant-exemption
   step was refuted — verification doc, slice 5.) Subject:
   `Graph::nodes()` topo order with a control-node producer edge on a
   value node — UNTESTED by anyone, and MEMORY warns against changing
   that walk. Build `Pi(value, guard=Proj)`, call `nodes()`, assert Proj
   precedes Pi and no existing node's relative order moves. **Establish
   RED status before writing any green; if it is green on arrival, record
   that and skip the step.**
4. **Wire round-trip, Chalk side.** `_extract_fields` (`JSON.pm:78`) and
   the deserialize chain (`:495-600`) gain Pi arms; without the emit arm
   a Pi serializes silently WITHOUT its piStamp. Check the `:477-479`
   forward-reference validator — it is Phi-hardcoded; a Pi's guard must
   serialize before the Pi or that validator needs a real change.
   `loader-reproduces-the-wire.t` must not rise.
5. **The scheduler delete — this is the SOUNDNESS step, not tidiness.**
   Verified: the spec's "soundness falls out of dominance" could not be
   confirmed — the backend's demand-driven emitter has an id-keyed value
   cache (`Context.pm:1253`) that would serve a guard-local ref outside
   its guard; the DELETE is what prevents it (the shipped bug class in
   `[[cross_graph_id_keyed_cache_collisions]]`). RED:
   `pi-deleted-by-scheduler.t` — after `schedule()`, no reachable node is
   a Pi and former consumers read the Pi's value input. GREEN: a use-def
   rewrite AFTER `schedule()` returns — a Pi is never IN the schedule
   (`EagerPinning.pm:57-79` builds `@body` from `control_in` only).
   UNVERIFIED that a consumer-rewrite helper exists on Node; establish
   before building. Verify `ir/llvm-stale-value-cache.t` and
   `ir/llvm-reassign-soundness.t`.
6. **Creation, Chalk's own frontend first.** Spec §5 assigns CREATE to
   "the only phase that sees `if (defined $x)` as syntax" — for the
   B::SoN path that phase does not exist (it walks the optree); Chalk's
   own `Bootstrap/Perl/Actions.pm` (7 `make('If')` sites) is the natural
   single-repo owner (spec erratum, §13). RED:
   `pi-narrows-under-defined-guard.t` — the use INSIDE the guard has the
   narrower effective stamp; the use OUTSIDE does not. T1's STRENGTHEN
   rule: a Pi's effective stamp is `refine(pi_stamp, input.stamp)`,
   RECOMPUTED, monotonic — its own rule in `%_COMPUTED_REPR` terms, not
   a join. Aliasing policy from the spec verbatim: a refinement holds
   only on a value that never leaves value-SSA. **Gate run G10.**
7. **Cross-repo, LAST.** perl5-son mirrors `Pi.pm` and creates Pis at its
   If sites (`FromOptree.pm:289` already builds Defined/Not; StackSim's
   `define` supplies rebinding). Coordinate; do not run `git zhi` in that
   repo; the no-producer-version-pin hazard applies — serialize all gate
   readings. **Gate run G11 (cross-repo).** UNVERIFIED:
   `SoN/Compare.pm`'s "Extra in B" behaviour for a one-sided Pi.

---

## 10. Gate schedule — where the coordinator runs the gate

The gate is `t/bootstrap/corpus/son-corpus-wide.t` (~10 min), floor
asserted at `:322` (`cmp_ok >= 218`; 215 after Phase 3 step 4 lowers it
per D2). ALWAYS run by the coordinator on
committed HEAD, never a subagent self-report; serialized (the gate reads
perl5-son live). Every step between gate runs is a separate commit,
independently revertible.

| Gate | After | Kind | Expected |
|---|---|---|---|
| G0 | Phase 0 | decisions recorded; D1/D2 ratified 2026-08-26 | DONE |
| G1 | Phase 1 step 6 | gate run | 218; wire.t = 16; all five assemblers through Pipeline or STOP |
| G2 | Phase 2 step 1 | gate run | 218 exactly (scratch experiment predicts byte-identical); any movement = revert, not patch |
| G3 | Phase 2 step 3 | gate run + scratch revert-independence check first | 218 |
| G4 | Phase 2 step 4 | gate run + 25 affected files + 3 silent-survivor hand-reads | 218 |
| G5 | before Phase 3 step 2 | measurement only (both `_element_repr` callers, freeze count, `:1598` reachability) | remedy decided from data |
| G5b | Phase 3 step 4 | gate run | 215 exactly (218 − L3b/L3c/L3d); anything else falsifies the D2 accounting |
| G6 | Phase 3 | gate run | 215 and MUST NOT MOVE further — unless step 5's measurement found live-guess cases, in which case the drop equals those cases, each a named latent miscompile surfaced (perigrin rules before landing) |
| G7 | before Phase 4 step 3 | measurement only (multi-callsite callee census) | test strategy calibrated |
| G8 | Phase 4 | gate run + white-box internal callers + `lli==perl==99` for B5 | ≥ 215; a raise is legitimate (2547-GAP cases going green) and is taken per §9.3 pairing |
| G9 | Phase 5 step 4 | gate run | **215 AND wire.t = 0, in the same run** — the spec-§7 acceptance |
| G10 | Phase 6 step 6 | gate run | 215 |
| G11 | Phase 6 step 7 | cross-repo gate | 215 |

Standing at every gate: `loader-reproduces-the-wire.t` never RISES above 16
(target 0 at G9); every RED is proven red before its green. Only three
places may move the number — Phase 3 step 4 (218 → 215, D2), Phase 3
step 5 (surfaced guess-miscompiles, perigrin rules per-site), Phase 4 (a
raise). Nothing else may move it.

---

## 11. Out of scope, and where each deferral lives

| Deferred item | Why | Tracked where |
|---|---|---|
| T2 (encoding transform) | its own project; spec §1 defines it | file on zhi when Phase 5 completes: "T2 — the encoding transform (Scalar→%Slot, merge boxing, Undef singleton)" |
| **Restoration of L3b/L3c/L3d to GREEN (gate 215 → 218)** | requires T2's `Scalar` encoding (D2) | **FILED HERE, 2026-08-27, as Phase 3 step 4 landed the drop.** BLOCKED-BY: T2. Scope: give `Scalar` a machine encoding, then revert the three `L: GAP(the merge is Scalar ...)` declarations in `t/corpus/mdtest/logical.md` (L3b, L3c, L3d) to `L: GREEN`, restore the spec §9.5 floor to 218, and raise the `son-corpus-wide.t` floor assertion from 215 back to 218. The IR-block stamps (`:Scalar` on the DefinedOr/Phi and their Coerce arms) are CORRECT and must NOT be reverted — the join is right; only the encoding is missing. **T2 is not done while the gate reads 215.** Not on zhi by instruction; this table is the record. |
| `%LOWERABLE_STAMP` + Print→Boolean seed removal | spec §8: deletable only when T1's exit-Unknown count is zero | named step of the T2/exit-zero follow-up; re-check the nine `_is_narrowed` guard sites then |
| `_build_registry_from_mop` retirement | derives six facts the MOP lacks | `docs/plans/2026-06-11-*` LLVM-reads-MOP line (zhi chain "MOP migration") |
| MOP round-trip through `to_json` | `to_json` emits only `{version, source, methods}` | file on zhi with the T2 chain; until then the Graph-mop invariant is not asserted on reloaded graphs |
| Analysis passes rewritten to pure edge traversal (the Phase-5 fence) | transitional `%graphs` hash inside `Analysis.pm` | file on zhi at Phase 5: "drain the fenced graph-hash: one pass at a time onto edge traversal" |
| Pipeline.pm moving `t/lib` → `lib/` | no production entry point exists (the end-to-end pipeline lives only under `t/lib` — a standing finding) | the executables line of work (`[[executable_gate_state_and_call_design_history]]`) |
| Method `return_type` on the wire (old slice 2b) | producer stores methods as bare strings (`B/SoN.pm:888`); cross-repo | file on zhi: producer-side method metadata record |
| Aliasing-policy liberalisation (spec §5 candidates) | optimization; needs escape analysis | spec §5 names it future optimizer work; revisit after Phase 6 |
| Guard-reporting diagnostics | speculation before the analysis exists | old plan's deliberate deferral, still deliberate |
| Scheduler namespace split (`Elaborate` → `Target::LLVM::`) | tangles with T2's extraction | lands with T2 |

---

## 12. UNVERIFIED registry (what would settle each)

Carried forward or newly introduced; do not build a gate on any of these.

- **Pipeline.pm ~120 lines; T1 delegation shim size** — estimates of
  unwritten code. Settled by writing them.
- **phase5-lib-coverage.t diag determinism** — settle by two consecutive
  runs diffed; until then compare the four named scalars only.
- **executable-gate.t scored-PASS output shape** — settle by running it
  once before Phase 1 step 3.
- **MOP::Class parent/MRO traversal usable for method resolution** —
  settle by reading `lib/Chalk/MOP/Class.pm` before Phase 2 step 3.
- **Phase 2 step 3 revert-independence** — settle by the G3 scratch
  experiment (land 1+2+3, revert 3, confirm gate returns).
- **"only 4 multi-callsite callees, zero polymorphic"** — settle at G7.
- **The 240-case join census and 218-case node census exact counts** —
  mechanisms verified, counts unreproducible; re-derive if a revert
  criterion needs them (G5 does this for the join).
- **~13 of 17 inline `from_json`+`lower` unit tests' "out of scope"
  classification** — settle by reading them at Phase 5 step 4, where they
  get the helper anyway.
- **The ~34 from_json test-caller count at this HEAD** — re-derive by grep
  at Phase 5 step 4.
- **`Graph::nodes()` topo behaviour with a control-producer edge on a
  value node** — Phase 6 step 3's whole content is establishing this.
- **Node consumer-rewrite helper existence** — settle by reading
  `Node.pm` before Phase 6 step 5.
- **`SoN/Compare.pm:106` "Extra in B" for a one-sided Pi** — settle in
  perl5-son before Phase 6 step 7.

---

## 13. Open questions for perigrin (spec touches — flagged, not edited)

1. **Spec §5 erratum.** "The frontend CREATES a Pi… the only phase that
   sees `if (defined $x)` as syntax" — on the B::SoN path no phase sees
   syntax; Chalk's own `Actions.pm` does (Phase 6 step 6 proceeds on that
   basis). The spec sentence should eventually say "the frontend" without
   the syntax rationale, or name both frontends. Also: spec §5's worked
   example remains a SPEC GAP until D1's vocabulary is written; the fix is
   additive (a `refine()` beside `meet_types`), so no landed join pin
   moves.
2. **Spec §4 gap: `meet_types` (and `refine`) can return `None`.** A Pi
   whose piStamp contradicts its input yields the lattice bottom — an
   unreachable-branch fact. The exit condition never discusses `None`. Is
   it a GAP, a dead-code fact for the optimizers, or §3-style
   contradiction evidence (die)? Needed by Phase 6 step 6, not earlier.
3. **Phase 3 step 5's expected finding.** If the guess-site measurement
   shows corpus cases reaching a live `// 'Int'`, the gate will drop when
   the guess becomes a GAP — each such case is a latent miscompile at
   HEAD. Standing instruction requested: land the loud GAP and lower
   nothing else, or hold that site until a fix exists?

---

## PHASE 1 AUDIT (coordinator, 2026-08-30)

Audited against Phase 1's own step list rather than against memory, after
"largely landed" was used here as a hedge for an unrun check.

**Steps 1-7: ALL COMPLETE.**

| step | deliverable | state |
|---|---|---|
| 1 | `t/bootstrap/codegen-harness/pipeline.t` + `Pipeline.pm` | present; **38/38 green** |
| 2 | Phase5LibCoverage migrated | `Pipeline`=5, `from_json`=0 |
| 3 | ProgramRunner migrated | `Pipeline`=2, `from_json`=0 |
| 4 | Mode2Adapter migrated | `Pipeline`=2, `from_json`=0 |
| 5 | son-e2e.t migrated | `Pipeline`=3, `from_json`=0 |
| 6 | son-corpus-wide.t migrated | `Pipeline`=2, `from_json`=0 in code |
| 7 | `transforms` threaded per graph | `Pipeline.pm:19,83`; pinned by pipeline.t 25/33/34 |

**No assembler is left inline.** Phase 1's stop condition ("If any assembler
is left inline, STOP") is not triggered.

A `grep -rln from_json t/` returns 44 files, which looks alarming and is not:
Phase 1 explicitly scopes out "the ~17 other `t/bootstrap/*.t` files doing
`from_json`+`lower` inline for single-purpose unit tests … they migrate, if at
all, in Phase 5". Those are not assemblers of the full sequence. An earlier
reading of that 44 as a Phase-1 gap was wrong.

**Two exit conditions are NOT met, and neither is code:**

1. **`loader-reproduces-the-wire.t` DOES NOT EXIST.** The exit says it "still
   reads 16". No file of that name is anywhere in `t/`. Same pattern as Phase
   2's `call-target-is-a-metaobject.t` and `call-node-resolved-handle.t`, also
   named as existing and also absent. Either these were renamed and this plan
   is stale about its own pins, or they were never written and the regression
   coverage those phases claim is imaginary. **Resolve before trusting any
   phase's exit criteria.**

2. **The G1 gate run reads 205 against a stated floor of 218** (the floor
   assertion itself was since lowered to 215 by D2, and the gate is failing
   even that: `not ok 247`). The floor text says "215 is a CEILING as well as
   a floor" and "T2 is not done while this reads 215". It reads 205. Whether
   that 10-case gap predates this session is UNMEASURED and is the next thing
   to bisect — a gate failing its own floor cannot validate a phase exit.

**Conclusion: Phase 1's code is done; Phase 1 is not exited.** The blocker is
not implementation but the two conditions above, and both are shared with later
phases rather than local to this one.

## PHASE 2 AUDIT (coordinator, 2026-08-30)

**Steps 0-3: ALL COMPLETE, including the amended scope.**

| step | deliverable | state |
|---|---|---|
| 0 | `mop-rides-on-the-graph.t` RED pin | present, **3/3 green** |
| 1 | classes guard dissolved; `defined $mop` deleted | `Analysis.pm:196` unguarded; no `wantarray` in JSON.pm |
| 2 | `Graph` carries the MOP | `Graph.pm:20` `field $mop`, `:22` `set_mop` |
| 3 | method dispatch onto the edge | `Analysis.pm:538` handles `'method'` ahead of the `'direct'` filter |
| 3-amend | `declare_method` threads the wire type | `Analysis.pm:1059`; `MOP::Method::set_return_type` narrows-only (`:50`) |
| 3-amend | the wire-vs-graph die re-sourced, not weakened | `Analysis.pm:1768` — the wire value rides the metaobject |

The three pins the phase names all pass at exactly the predicted counts:
`call-target-is-a-metaobject.t` **5/5**, `call-node-resolved-handle.t` **7/7**,
`mop-rides-on-the-graph.t` **3/3**.

### CORRECTION to the Phase 1 audit above

**The "missing pins" finding in the Phase 1 audit was WRONG, and so was the
same claim about Phase 2's pins.** All three exist and are green:

- `call-target-is-a-metaobject.t` and `call-node-resolved-handle.t` are in
  `t/bootstrap/mop/`; I searched only `t/bootstrap/ir/`.
- `loader-reproduces-the-wire.t` is in `t/bootstrap/ir/`; my `find` over `t/`
  timed out and I read the empty result as absence.

Git confirms both were added (2026-08-20, 2026-05-20) and never deleted. The
plan is NOT stale about its own pins, and the regression coverage is real.
**Strike the "resolve before trusting any phase's exit criteria" warning in the
Phase 1 audit — it rested entirely on this error.**

`loader-reproduces-the-wire.t` passes 4/4. Phase 1's exit says it "still reads
16"; it reports four subtests, so the 16 is either a stale count or refers to
something the file no longer prints — worth a look when Phase 1 is formally
exited, but it is passing, not missing.

**A search that finds nothing is not evidence of absence** — it is evidence the
search was wrong until the search itself is verified. Two of today's findings
died on this.

### What remains for BOTH phases

One thing, shared: **the gate reads 205 against a floor of 215** (`not ok 247`).
Neither phase can be formally exited on a gate failing its own floor, and
whether that gap predates this session is still unmeasured. That is now the only
open blocker for Phases 1 and 2 — everything else in both is done and green.

## THE 205-vs-215 BISECT (coordinator, 2026-08-30)

Measured against a PINNED producer (`8c15e32`) at every step, so the producer
could not move underneath the measurement — the failure that made an earlier
reading of 162 look like a regression.

| commit | gate-green | |
|---|---:|---|
| `bdb74505` restore the coercion passes | **207** | session baseline |
| `6db5dcdc` Scalar is refinable | **206** | −1 |
| `5b5c98a1` fixpoint folds the old value | 206 | |
| `45eb3183` round cap | 206 | |
| `ebdd6a23` field store coherent by encoding | 206 | |
| `6b0e45f0` Scalar is lowerable | **205** | −1 |
| `17ba4c08` Num field payload | 205 | |
| HEAD | **205** | |

**The gap is 2 cases, not 10, and both are mine.** The floor of 215 was never
met during this session — `bdb74505` already read 207 — so 215 reflects a state
before the session and the "10 cases below floor" framing was wrong.

**Case 1, lost by `6db5dcdc`: `classes: arrayref-field element read`**

    GAP: Call(method) 'first' node repr=Int disagrees with class 'Bag'
         vtable ABI return_repr=Scalar

**Predicted in that commit's own message** and then lost track of: making
`Scalar` refinable means a node correctly narrows `Scalar -> Int` while the
vtable does not follow, and an ordered comparison reads the refinement as a
disagreement. `Int <: Scalar` — a refinement, not a contradiction.

**Case 2, lost by `6b0e45f0`: `subs: F8 positional $_[0] subscript`**

    lower: Add with repr=Scalar ...

Admitting `Scalar` to the representation field means an `Add` now legitimately
carries `Scalar`, which the backend has no arm for. Same shape as case 1: the
type answer got better and a consumer that assumed it could not be `Scalar`
now refuses it.

**Both are the SAME defect class, and it is the one this session kept finding:**
a consumer written when `Scalar` could not appear, now meeting a `Scalar` that
is correct. `%LOWERABLE_STAMP`, the field-store `ne`, the vtable ABI check, the
"cannot lower Scalar" die — all the same. These two are the remaining members,
now named.

**Neither is a miscompile.** Both are honest GAPs, zero behavioural mismatches
throughout. The trade was: 21 GAPs closed by `6b0e45f0` against 1 case moved to
a GAP — recorded here so the ledger is explicit rather than implied.

**What this unblocks.** The gate is now READABLE: 205 is explained, both losses
attributed, and a change that moves it can be read against a known baseline.
Phase 1 and Phase 2 can be formally exited once these two are closed or
accepted; the coercion handoff (StrEq first) has a measurable floor to work
against.

## PHASE 3 AUDIT (coordinator, 2026-08-30)

Audited step by step. An earlier note in this session called Phase 3 "landed"
on the strength of two greps; this is the real check.

**Steps 1-4: ALL COMPLETE.** Every value the plan pins was verified by
execution against `_join_repr`, not by reading:

| step | deliverable | verified |
|---|---|---|
| 1 | absorb — `join(Int,Unknown) = Unknown`, both arm orders | **yes**, and `join-drops-unknown.t` is renamed to `join-absorbs-unknown.t` |
| 2 | the total fold | **every pin matches**: `(Undef,Int)→Scalar`, `(ArrayRef,Int)→Scalar`, `(Array,Int)→List`, `(Boolean,Int)→Str`, `(Slot,Int)→Unknown`, `(Slot,Slot)→Slot` |
| 3 | delete the dead `'same'` branch | **gone** |
| 4 | the D2 Undef-drop deletion | landed 2026-08-27 with a full node-by-node stamp diff (2971 stamps each side, 5 nodes differ across exactly 3 cases); the three GAP declarations are in `logical.md` and the floor reads 215 |

### The B3 remedy the plan REFUSED — and why today's work made it safe

Step 4 records that the favoured remedy, *teaching `_is_narrowed` that `Scalar`
is refinable*, **DOES NOT TERMINATE**: L3b reached iteration **457,642** and was
still climbing. The measured mechanism: *"all six `$changed = 1` sites in
`_propagate_computed_reprs` are UNCONDITIONAL — none tests whether the repr
actually moved. Loop termination rests ENTIRELY on `_is_narrowed` acting as a
one-shot latch."*

**`6db5dcdc` did exactly what the plan refused** — and it terminates, because
the same commit replaced the latch it removed. Verified at HEAD: of the four
write sites in that loop, **three now carry `next if defined $prev && $prev eq
$repr`**, the change guard. The fourth writes the CONSTANT `'Undef'`, so it
converges after one write and cannot oscillate.

So the plan's cost comparison was right about the code as it stood, and the
refusal was correct at the time. What changed is not the judgement but the
precondition: **the latch was replaced before the thing that depended on it was
removed.** `5b5c98a1` then added the other half of Kildall's discipline (fold
the old value into the join), so the chain is monotone as well as guarded.

The two cases this cost are named and attributed in the bisect entry below;
neither is a miscompile.

**Phase 3 needs no further work.** Its remaining item is not a step but a
consequence: restoring L3b/L3c/L3d to GREEN and the floor to 218 is **T2's**
acceptance criterion, which is blocked on T1 completing.
