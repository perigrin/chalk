# T1 architecture plan — from HEAD to the spec, decomposed around prerequisites

**Date:** 2026-08-26
**Status:** PLAN. Replaces the slice-4 decomposition (4a–4e) of
`docs/plans/2026-08-24-loader-analysis-pipeline.md`, which failed build
verification (`docs/plans/2026-08-26-slice4-build-verification.md`: five
NEEDS_REWORK verdicts, six BLOCKING findings, six cross-slice conflicts).
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

What exists at HEAD, stated the way the verification established it (the old
plan had both of these inverted):

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
| §1 no guessing | FOUR live `$repr // 'Int'` backend guesses: `Target/LLVM/Context.pm:3349, :4071, :5801, :6827` (all four re-verified verbatim at HEAD) — B4, unowned by the old plan |

---

## 2. Why this factoring, not the old one

The old plan decomposed around EXISTING PASS NAMES (the join, the analyses,
the pipeline, the MOP, the Pi) and every blocking finding landed BETWEEN its
units: B1 spanned 4c/4b/4e, B6 spanned 4e/4a two slices apart, B4 fell
between all of them, B2 depended on T2 which no unit built. The units were
individually plausible and collectively unable to catch their own conflicts.

This plan decomposes around **what must be true before T1 can exist**, in
dependency order, with a decision phase in front. The verification kept the
old ordering (4c→4d→4a→4b→4e) as sound in dependency DIRECTION; this plan
keeps that direction and changes the units:

- **Phase 0** makes every decision whose absence caused a cross-slice
  conflict, BEFORE any code (B6/C3 is the model: the piStamp vocabulary
  choice silently falsifies phase-3 join pins if made in phase 6).
- **Phase 5 exists at all.** The old plan improved `Analysis.pm` in place
  and never contained the step where `Chalk::IR::Transform::TypeInference`
  is BORN with the spec-§2 contract and `from_json` stops analysing. That
  step — the one the spec is about — had no owner. It is now a phase.
- **B4 has an owner** (phase 3): the backend guesses retire in the same arc
  that makes the join total, because a total join is what makes "repr absent
  at the backend" a bug rather than a Tuesday.
- **Every seam introduced conforms to `$graph -> $graph` from its first
  commit** (B1): the pipeline's transforms slot threads per-graph; T1's
  public contract is per-graph; the one transitional whole-set hash is
  fenced inside module privacy with a filed migration (§Phase 5).

How the six blockers are disposed of:

| Blocker | Disposition |
|---|---|
| B1 graph-set shape | Resolved by construction: Phase 1 step 7 ships `transforms => [$g -> $g]`; Phase 5 births T1 with `run($graph)`; the transitional hash is fenced (Phase 5, "the fence") |
| B2 Undef-drop vs the 218 floor | RULED: deletion is IN SCOPE (Phase 3); gate 218 → 215 with three declared GAPs; spec §9.5 amended in the same commit; restoration is T2's acceptance criterion |
| B3 fixpoint freezing + second `_element_repr` caller | Discharged by a mandatory measurement gate (G5) BEFORE the total-join lands; the remedy is chosen from that data (Phase 3 step 0) |
| B4 `$repr // 'Int'` | Owned: Phase 3 step 4 converts all four sites to loud GAP dies, measured first |
| B5 DefinedOrFold store-blindness | Resolved by construction: the `_element_at` refusal lands in the SAME COMMIT as store-aware `_element_repr` (Phase 4 step 1), with `lli == perl == 99` as the acceptance test |
| B6 inexpressible piStamp | Phase 0 decision D1, made before any join pin lands. Recommended: separate refinement vocabulary, `%PARENT` untouched |

---

## 3. Phase 0 — decisions before code

No code. Each decision is recorded here with its recommendation; the two
that touch the spec need perigrin's ruling (see §11 Open Questions). Do not
start Phase 1 until D1 and D2 are ratified.

**D1 — piStamp vocabulary (resolves B6/C3).**
`TypeLibrary.pm:17-56` places `Undef` as a SIBLING of `Str`/`Num`/`Ref`
under `Scalar`; there is no complement operator; `meet(Scalar,Scalar) =
Scalar`, so the spec §5 worked example (`if (defined $x)`) has no
expressible piStamp today. Two options:

- **(a) RECOMMENDED: a separate refinement vocabulary.** `piStamp` values
  are a small closed set (initially just `NotUndef`) with their own
  `refine($pi_stamp, $lattice_type)` meet against lattice types, defined
  beside `meet_types` in TypeLibrary. `%PARENT` is untouched, so every
  `join_types` pair — including the phase-3 pins `Boolean,Int -> Str`
  (ruled INTENDED by perigrin) — keeps its meaning.
- **(b) reparent `%PARENT`** (add a `Defined` member, move `Str`/`Num`/…
  under it). Changes `join_types` for existing pairs and silently falsifies
  phase-3 contract tests landed two phases earlier. Take only with explicit
  sign-off, and then write phase-3 pins against the FINAL lattice.

**RULED BY PERIGRIN 2026-08-26: (a).** `%PARENT` is NOT reparented; piStamp
is a separate refinement vocabulary. Phase 3 may pin join results against the
lattice as it stands today.

**D2 — the Undef drop IS DELETED; the gate drops 218 → 215 (resolves B2).**
Deleting `Analysis.pm:1228-1241` moves L3b/L3c/L3d GREEN → GAP because
`Scalar` has no machine encoding until T2 exists (`Context.pm:3646-3651`,
`:3676-3682` — dies).

**RULED BY PERIGRIN 2026-08-26: the temporary drop is acceptable.** The
deletion is IN SCOPE for Phase 3. Consequences, which the builder must honour:

- **Spec §9.5's floor becomes 215** for the duration, with L3b/L3c/L3d
  DECLARED GAPs naming `Scalar` and pointing at T2. Amend §9.5 in the same
  commit as the deletion — an unamended spec and a 215 gate is drift.
- **215 is a CEILING as well as a floor while it stands.** A fourth case going
  GAP is a regression, not more of the same; the three are named so a fourth
  is visible.
- **The restoration is T2's acceptance criterion, not a wish.** File it as
  blocked-by-T2: "restore L3b/L3c/L3d to GREEN; gate returns to 218." T2 is
  not done while the gate reads 215.
- This is the invariant working as designed: a declared GAP is acceptable, a
  silent wrong answer is not (spec §1). The drop buys a total join, which is
  what makes the guesses in D3 retireable.

**D3 — the backend guesses become GAPs (resolves B4).** DECIDED IN-PLAN.
The four `// 'Int'` sites convert to loud dies in Phase 3, after measuring
which corpus cases reach each site. Rationale: spec §1's table — a guess is
the only unacceptable outcome; a GAP is acceptable. Removing loader
compensations (this plan's whole direction) makes the guesses MORE
reachable, so they cannot outlive the compensations.

**D4 — the transform contract is `$graph -> $graph`, per graph.** DECIDED
by spec §2; recorded because the old 4c design violated it
(`transforms => [sub ($graphs,$mop) {...}]`). Every seam in this plan
threads transforms per graph. Whether a whole-set hash may survive
PRIVATELY inside a module during transition: yes, fenced — see Phase 5.

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
instead of five. The 2026-08-25 incident (gate 218 → 136 because the
assemblers broke simultaneously) is the empirical argument; C5 says both
later high-risk steps re-create that mechanism if ANY assembler stays
inline. Five, not three — the fourth is the gate itself
(`son-corpus-wide.t:60-119`), the fifth is `son-e2e.t:66`.

New file: `t/lib/Chalk/CodeGen/Pipeline.pm` (~120 lines — UNVERIFIED, an
estimate of unwritten code). Under `t/lib` because every caller is
test-tier and `lib/` has zero (verified: no production code calls
`from_json` at all); it moves to `lib/` when a production entry point
exists (§9 deferrals).

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

**Goal:** spec §6. The strongest of the old sub-slices; its riskiest step
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
   deferred (§9).
3. **Method dispatch onto the edge** — the step that makes spec §2 true
   and the step the old plan did not contain. RED: subtest 4 — a
   `Child->new->m` method-dispatch Call's `target` is a
   `Chalk::MOP::Method`. Fails at `:487-490`'s `eq 'direct'` filter.
   GREEN: widen `_attach_call_targets` to `'method'`, resolving through
   `$mop->for_class(...)` and the parent chain — **UNVERIFIED that
   MOP::Class exposes a usable parent/MRO traversal; check before
   building** — and rewrite `_stamp_method_call_reprs` (`:1626-1642`) to
   read `$node->target->return_type`. KEEP the wire-vs-graph disagreement
   die at `:1598-1605` — load-bearing. **Before landing, settle the OPEN
   DISAGREEMENT on revert-independence in scratch**: land 1+2+3, revert 3
   alone, confirm the gate returns to its post-step-2 value (step 3
   rewrites resolution inside the `:238` fixpoint that step 1 newly
   feeds). **Gate run G3.**
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
5. **Do NOT delete `_build_registry_from_mop`.** It derives six classes of
   fact the MOP does not hold (vtable slots, flattened inheritance,
   exactly-one-Return enforcement, return-repr fallback, `:reader`
   synthesis records, two policy filters — all six re-confirmed). Its
   retirement belongs to the LLVM-reads-MOP work (§9).

---

## 6. Phase 3 — the total join, and the guesses retire

**Goal:** spec §10 (absorb) and §1 (no silent guess), on the join that
every Phase-4 analysis folds over. All landing steps are measured
corpus-inert; the phase is bracketed by a measurement gate in front (B3)
and a must-not-move gate run behind.

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
   `:1240` runs ahead of the join and stays, per D2).
3. **Delete the dead `'same'` branch** (`:1218-1226`; `:1192` becomes
   `if ($rule ne 'join')`). Dead since 6d9fc083 — `%_COMPUTED_REPR` maps
   And/Or to `'join'`; nothing maps to `'same'`. No red test can exist for
   unreachable code; the honest check is a coverage assertion that no
   `%_COMPUTED_REPR` value is `'same'`. **Commit separately** so any gate
   movement is attributable.
4. **The guesses become GAPs (B4, D3).** First MEASURE which corpus cases
   reach each of `Context.pm:3349`, `:4071`, `:5801`, `:6827` (an
   `warn`+run over the corpus in scratch — not committed). Then RED: a
   unit test per site driving a repr-less node into it, asserting a die
   whose message names the node and the missing repr (GAP shape, not
   `Int`). GREEN: `// 'Int'` → `// die "GAP: ..."`. `:3349` is on the
   DefinedOr phi path — if the measurement shows corpus cases reaching a
   site with a live guess, THAT IS A LATENT MISCOMPILE at HEAD; report it
   to perigrin before converting, since conversion will move the gate
   (GREEN → GAP is a gate drop that this plan treats as a finding, not a
   regression — see §10 honesty note).
5. **Exit: G6 gate run.** Floor 218 and the count must NOT move (all
   landed steps are corpus-inert; movement falsifies the inertness claim).
   Exception: if step 4's measurement found live-guess cases, the expected
   number is 218 minus those cases, each now a loud GAP naming a real bug
   — perigrin decides between landing that and reverting the specific
   site pending a fix.

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
5. **Exit: G8 gate run.** Floor 218; expected movement: cases that
   previously GAPped at `Context.pm:2547` on heterogeneous stores may go
   green — a floor RAISE, taken only on a run where the gate holds
   (spec §9.3 pairing rule).

---

## 8. Phase 5 — T1 is born, and the loader stops analysing

**Goal:** the step the old plan never contained. After phases 1–4 the seam
exists, the edge is total, the join is total, the analyses traverse edges.
Now the class exists and the fusion ends.

1. **The class, with the spec-§2 contract.** RED: new
   `t/bootstrap/transform/type-inference-contract.t` — 
   `Chalk::IR::Transform::TypeInference->new->run($graph)` returns a
   graph; a Value node arriving stamp-less is `Unknown` after entry
   normalization (spec §4); control nodes are untouched. GREEN: new
   `lib/Chalk/IR/Transform/TypeInference.pm` whose body DELEGATES to the
   existing `Analysis` sequence. **The fence:** internally, the transform
   reaches the program from `$graph` — via `$graph->mop` (Phase 2) it
   enumerates the compilation unit's graphs and hands the existing passes
   the `%graphs` hash they still take. That hash is PRIVATE, never in any
   signature outside `Analysis.pm`, marked at its one construction site
   with a comment naming this paragraph, and its elimination (each pass
   rewritten to pure edge traversal) is the filed migration in §9. T1 is
   born conforming; the debt is inside, fenced, and named. **Class
   metadata:** the loader attaches the DECODED wire `classes` section to
   graphs (pure deserialization — reproducing what the frontend
   serialized); T1 reads it from the graph, builds and seals the MOP
   mid-run (structurally forced, Phase 2 step 2), attaches it at exit.
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
   holds at **218**. One change does both or the seam is wrong.
   **Gate run G9.**
5. **What does NOT happen here:** `%LOWERABLE_STAMP` and the
   Print→Boolean seed stay in place until the exit report's `Unknown`
   count reaches zero (spec §8: the filter is deletable on T1's
   COMPLETION — while Unknowns still leave T1, the filter is what keeps
   the poison value out of the shared stamp/representation field, per the
   old plan's 3b record). Tracked in §9.

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
3. **Topo order, red status unknown.** The old step here (TypedInvariant
   exemption) was REFUTED by execution — `representation()` is on the
   Node base class and both cited sites already skip undef on the next
   line; the proposed red was vacuously green. Replacement subject:
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
   single-repo owner (spec erratum, §11). RED:
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

## 10. Gate schedule — where the coordinator runs the 218

The gate is `t/bootstrap/corpus/son-corpus-wide.t` (~10 min), floor
asserted at `:322` (`cmp_ok >= 218`). ALWAYS run by the coordinator on
committed HEAD, never a subagent self-report; serialized (the gate reads
perl5-son live). Every step between gate runs is a separate commit,
independently revertible.

| Gate | After | Kind | Expected |
|---|---|---|---|
| G0 | Phase 0 | decisions recorded, D1/D2 ratified by perigrin | — |
| G1 | Phase 1 step 6 | gate run | 218; wire.t = 16; all five assemblers through Pipeline or STOP |
| G2 | Phase 2 step 1 | gate run | 218 exactly (scratch experiment predicts byte-identical); any movement = revert, not patch |
| G3 | Phase 2 step 3 | gate run + scratch revert-independence check first | 218 |
| G4 | Phase 2 step 4 | gate run + 25 affected files + 3 silent-survivor hand-reads | 218 |
| G5 | before Phase 3 step 2 | measurement only (both `_element_repr` callers, freeze count, `:1598` reachability) | remedy decided from data |
| G6 | Phase 3 | gate run | 218 and MUST NOT MOVE — unless step 4's measurement found live-guess cases, in which case the drop equals those cases, each a named latent miscompile surfaced (perigrin rules before landing) |
| G7 | before Phase 4 step 3 | measurement only (multi-callsite callee census) | test strategy calibrated |
| G8 | Phase 4 | gate run + white-box internal callers + `lli==perl==99` for B5 | ≥ 218; a raise is legitimate (2547-GAP cases going green) and is taken per §9.3 pairing |
| G9 | Phase 5 step 4 | gate run | **218 AND wire.t = 0, in the same run** — the spec-§7 acceptance |
| G10 | Phase 6 step 6 | gate run | 218 |
| G11 | Phase 6 step 7 | cross-repo gate | 218 |

Standing at every gate: `loader-reproduces-the-wire.t` never RISES above 16
(target 0 at G9); every RED is proven red before its green (two of the old
plan's reds were demonstrably vacuous; one more was green-on-arrival after
re-scoping).

**Honesty about the number:** two places in this plan can legitimately move
it. Phase 3 step 4 can DROP it by surfacing latent guess-miscompiles as
loud GAPs — that is the project invariant working (GAP-not-miscompile), and
each such case is a bug report, not a regression; perigrin rules on landing
vs. deferring per-site. Phase 4 can RAISE it by fixing heterogeneous-store
containers. Nothing else may move it, and D2 parks the one old-plan step
that knowingly broke it.

---

## 11. Out of scope, and where each deferral lives

| Deferred item | Why | Tracked where |
|---|---|---|
| T2 (encoding transform) | its own project; spec §1 defines it | file on zhi when Phase 5 completes: "T2 — the encoding transform (Scalar→%Slot, merge boxing, Undef singleton)" |
| ~~Undef-drop deletion~~ — NO LONGER DEFERRED | D2 ruled 2026-08-26: in scope, Phase 3, gate → 215 | what IS deferred is the RESTORATION: file on zhi blocked-by-T2, "restore L3b/L3c/L3d to GREEN; gate returns to 218" — T2 is not done while the gate reads 215 |
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

1. ~~**D1 ratification.**~~ **RULED 2026-08-26: option (a)** — a separate
   refinement vocabulary; `%PARENT` is not reparented. Spec §5's worked
   example remains a SPEC GAP until the vocabulary is written; the fix is
   additive (a `refine()` beside `meet_types`), so no landed join pin moves.
2. ~~**D2 ratification.**~~ **RULED 2026-08-26: the temporary drop is
   acceptable.** The Undef drop is deleted in Phase 3, the gate goes to 215
   with L3b/L3c/L3d as declared GAPs, spec §9.5 is amended in the same
   commit, and restoration to 218 becomes T2's acceptance criterion.
3. **Spec §5 erratum.** "The frontend CREATES a Pi… the only phase that
   sees `if (defined $x)` as syntax" — on the B::SoN path no phase sees
   syntax (it walks the optree); Chalk's own `Actions.pm` does. Phase 6
   step 6 proceeds on Actions.pm as the single-repo owner; the spec
   sentence should eventually say "the frontend" without the syntax
   rationale, or name both frontends.
4. **Spec §4 gap: `meet_types` (and `refine`) can return `None`.** A Pi
   whose piStamp contradicts its input yields the lattice bottom — an
   unreachable-branch fact. The exit condition never discusses `None`. Is
   it a GAP, a dead-code fact for the optimizers, or §3-style
   contradiction evidence (die)? Needed before Phase 6 step 6, not before.
5. **Phase 3 step 4's expected finding.** If the guess-site measurement
   shows corpus cases reaching a live `// 'Int'`, the gate will drop when
   the guess becomes a GAP — each such case is a latent miscompile at
   HEAD. Standing instruction requested: land the loud GAP and lower
   nothing else, or hold that site until a fix exists?
