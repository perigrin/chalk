# T1 Slice 4 -- build-ready plan

*Compiled 2026-08-26 from five measurement passes, five adversarial verifications, and one cross-slice agentic review. Branch `phase5-capstone`, HEAD `d9515cc9`.*

Reading rules for this document:

- Every `file:line` below was verified at HEAD by a measuring agent **and** survived adversarial verification, or is the verifier's correction (marked **[VERIFIER CORRECTION]**).
- Claims a verifier could not confirm are marked **UNVERIFIED**. They are not laundered into confidence. Do not build a gate on one.
- Where measurement and verification conflict without resolution, both readings appear under **OPEN DISAGREEMENT** with the experiment that settles it.
- Settled, do not re-argue: absorb (`join(Unknown,T) = Unknown`), `Boolean <: Str` is INTENDED per the user, T1/T2 are correctness transforms.

---

## Verdict

**NEEDS_REWORK — but the ordering is RIGHT and is kept.**

**Build order: 4c → 4d → 4a → 4b → 4e.**

All five sub-slices came back NEEDS_REWORK from adversarial verification, and the agentic review found six BLOCKING issues. None of them impeach the dependency direction:

- **4c first** — the seam makes 4d's 27-site return-shape collapse one edit instead of 27. The 2026-08-25 incident (gate 218 → 136 because three assemblers broke simultaneously) is the empirical argument.
- **4d second** — a MOP on every graph is what 4b's edge-reads and 4e's strengthen phase traverse. Verified empirically gate-neutral (see 4d).
- **4a third** — the total join is the primitive every 4b analysis folds over.
- **4b fourth** — the four analyses are joins over gathered sets; they need 4a's fold and 4d's edges.
- **4e last** — largest, and the only cross-repo slice.

Four amendments are required for the ordering to deliver its claimed property (each step's verification surviving later steps):

1. **The 4e piStamp-vocabulary decision must be made BEFORE 4a lands its join pins.** 4e step 1 option (a) reparents `%PARENT`, which changes `join_types` for existing pairs and silently falsifies 4a's landed contract tests. Prefer the non-reparenting option. This is a decision, not code — it does not move 4e's implementation out of last position.
2. **4a must be split.** Steps 1–3 (absorb, total fold, dead-`same` removal — all measured corpus-inert) stay in position. Step 4 (Undef-drop deletion) conflicts with spec §9.5's 218 floor and depends on T2, which no sub-slice builds. Park it.
3. **4b must be re-scoped.** As written its first two steps re-implement 4a's fold and 4d's guard hoist on the same lines; under this ordering both red tests are green on arrival.
4. **4c must migrate ALL FIVE assemblers**, not the plan's three. With three-harness scope, the ordering's central justification ("one change does both") does not hold.

---

## Blocking issues

Six. Each is repeated at the head of its sub-slice section.

| # | Sub-slice | Issue |
|---|-----------|-------|
| B1 | 4c (+4b, 4e) | The graph-set shape spec §2 forbids is being institutionalized at the new seams |
| B2 | 4a | Step 4 knowingly moves the gate 218 → 215; spec §9.5 makes 218 an acceptance criterion |
| B3 | 4a | The total join creates a precision regression and an unanalyzed blast radius |
| B4 | 4a (+4b) | The plan's FOURTH improvisation (`$repr // 'Int'`) has no owner — four live sites |
| B5 | 4b | Analysis (iii) widens a known silent-miscompile divergence with DefinedOrFold |
| B6 | 4e (+4a) | `defined` has no expressible piStamp; the fix reparents the lattice under 4a's feet |

---

## Cross-slice conflicts

### C1 — Graph-set at the seams (4c ↔ 4b ↔ 4e ↔ spec §2)

Spec §2 (lines 45–58): *"ONE GRAPH. There is no 'graph set' in the architecture… There is no `Map<String, Graph>`"*; entry contract `run($graph) -> $graph`.

Plan lines 977–985, verified at HEAD: *"Written the other way, a builder would pass a hash of graphs and rebuild the shape the contract rejects."*

Three slices independently reach for that shape:

- 4c build step 1: `method run($json, $select)` where `$select` is `sub ($graphs, $mop)`.
- 4c build step 6: `transforms => [ sub ($graphs,$mop) { ...; return ($graphs,$mop) } ]` — and the transforms slot is **explicitly the T1 accommodation point**, so T1 would land as a `Map<String,Graph>` consumer.
- 4b's gather steps stay `($graphs)`-shaped ("sweep every graph, bucket by refaddr").
- 4e nominates `lib/Chalk/IR/Analysis.pm` as STRENGTHEN owner without flagging that every sub there iterates `keys %$graphs` — `_seed_and_propagate_reprs($graphs)`, `_propagate_computed_reprs($graphs)`, `_assert_value_nodes_are_typed($graphs)`.

No measurement argued the tension. The 4c verifier flagged it as the single unaddressed load-bearing design question in the slice; spec §11 does defer the pipeline's shape, so this is *arguably* permitted — but it must be argued explicitly, not omitted.

**Resolution, binding on 4c:** transforms are per-graph `$g -> $g` callables. After 4d the rest of the program is reachable from any graph via `Call->target->graph` and `$g->mop`, so a per-graph transform loses nothing. The Loader stage may internally hold the wire's methods container; nothing downstream of Load may receive the hash. 4b's gather steps become edge traversals from one graph per plan:981–983. If a transitional hash survives inside `Analysis.pm`, say so in a `# ponytail:` comment and file the migration.

### C2 — 4b duplicates 4a and 4d on the same lines

4b's "4a PREREQUISITE" step edits `Analysis.pm:1004-1027` and `:1218-1226` — 4a steps 1–3 exactly. 4b's step (i) hoists `_attach_call_targets` out of the classes guard and seals an empty MOP — `Analysis.pm:196-222`, 4d step 1 verbatim. Two builders executing as written collide; under this ordering 4b's `call-target-is-unconditional.t` is GREEN before 4b starts. Re-scoped below.

### C3 — 4e invalidates 4a's verification

4e step 1 option (a) reparents `%PARENT` (`TypeLibrary.pm:17-56`), adding a `Defined` member with `Str`/`Num`/`Int`/`Boolean`/`Ref` moved under it. That changes `join_types` for existing pairs. 4a's contract pins — `Boolean,Int -> Str` depends on the current `Boolean => 'Str'` and `Int => 'Num' => 'Str'` chains — are verified in slice-position 3 and silently falsified in position 5.

**Resolution:** make the representation decision now (see "What the coordinator must gate-verify", G0). Prefer piStamp as a small separate refinement vocabulary with its own meet against lattice types, leaving `%PARENT` untouched.

### C4 — 4a and 4d both feed the `_stamp_method_call_reprs` fixpoint and the `:1598` die

4d step 3 rewrites method-call resolution onto the edge and asserts revert-independence from steps 1–2. 4a later changes the join values flowing into the same fixpoint (`Analysis.pm:238`) and can newly trigger the wire-vs-graph die at `Analysis.pm:1598-1605` with `Scalar`. 4d's empirically verified gate run does not cover post-4a stamp values. The interaction is untested in either design.

### C5 — 4a step 4 and 4d step 4 both require complete 4c assembler migration

Both are behaviour changes routed through `from_json`. Any assembler left inline re-creates the 2026-08-25 mechanism. The plan knows of three; there are five.

### C6 — `lower_opts` placement

4c proposes `Pipeline->new(lower_opts => {...})` (constructor). Measured against that: `program_mode` is passed by 2 of 5 assemblers and must NOT be passed by the other 3, and `t/bootstrap/ir/emitted-ir-is-well-typed.t:108` toggles it **per case within one caller** (`($opt{fragment} ? () : (program_mode => 1))`). Fixing it on the object silently breaks Mode2Adapter's type-tagged oracle (contract C). It rides on `run()`.

---

## 4c — the pipeline object

**Verdict: NEEDS_REWORK. Build after fixing B1 and the assembler census.**

### BLOCKING — B1: the graph-set shape at the transforms seam

This section opens with it because the transforms slot is the T1 accommodation point. Ship it as `sub ($graphs,$mop)` and T1 is born a `Map<String,Graph>` consumer, against spec §2 and against the plan's own warning at 977–985.

Fix before writing any 4c code: `transforms => [ $g -> $g ]`, per graph. See C1.

### Blockers — true today?

| Requirement | True today | Evidence |
|---|---|---|
| The three named harnesses exist under `t/lib/` | **true** | `find t/lib -name '*.pm'` → 19 files incl. all three |
| All three run `from_json` then `->lower` inline | **true** | ProgramRunner.pm:199+:207; Mode2Adapter.pm:159+:166; Phase5LibCoverage.pm:71+:111 |
| The three sequences are IDENTICAL (plan's word) | **FALSE** | Differ in producer flags, `program_mode`, entry selection, failure policy — each load-bearing |
| There are exactly three such assemblers | **FALSE — there are FIVE** | **[VERIFIER CORRECTION]** measurement said four; `son-e2e.t:66` is the fifth |
| T1 exists to be a pipeline stage | **FALSE** | `find lib -path '*Transform*'` → nothing |
| T2 exists to be a pipeline stage | **FALSE** | same |
| An Optimizers stage the harnesses invoke | **FALSE** | grep for Optimizer across all assemblers: zero hits |
| A Scheduler stage is a separate invocable step | **FALSE** | scheduling is INSIDE `lower()` — `Target/LLVM.pm:53-58` |
| `from_json` is a pure loader | **FALSE — the crux** | `Serialize/JSON.pm:707` calls `Analysis->run`; that is Analysis's ONLY caller repo-wide |
| `loader-reproduces-the-wire.t` reads 16 | **true** | ran it; `# TOTAL stamp differences across the round trip: 16` |
| No `lib/` code calls the `from_json`→`lower` sequence | **true** | all 20 such files are under `t/` or `scratchpad/` |

The last-but-one row reframes the whole sub-slice: **4c is not assembling stages, it is creating a seam OUTSIDE `from_json` so the already-fused Loader+Analysis can later be split.** `Serialize/JSON.pm:701-706` says so in a comment: *"from_json should not call this at all… The call stays only so the ~40 existing callers keep working during the transition."*

### Verified edit surface

| File | Line | What is there now | What must change |
|---|---|---|---|
| `t/lib/Chalk/CodeGen/Pipeline.pm` | — | DOES NOT EXIST | NEW FILE. Under `t/lib` because all callers are test-tier and `lib/` has zero. Moves to `lib/` in a later slice when a production entry exists. |
| `t/lib/Chalk/CodeGen/Harness/ProgramRunner.pm` | 199 | `my ($graphs,$mop) = eval { ...from_json($json) };` | → `Pipeline->run`. Span 199–210 = 12 lines |
| ″ | 201 | `$graphs->{'main::__PROGRAM__'} // $graphs->{'main::__main__'}` | becomes the entry selector param |
| ″ | 206 | `lower($ret, program_mode => 1, mop => ...)` | moves into Pipeline; `program_mode` per-**call** |
| ″ | 207 | `(defined $mop ? (mop => $mop) : ())` | **[VERIFIER ADDITION]** conditional-spread; 4d changes what the backend receives here for 186 cases |
| ″ | 137 | `TypedInvariant->check($graph)` idiom | OPTIONAL — slice 5's exit gate. Leave for 4c |
| `t/lib/.../Mode2Adapter.pm` | 159 | `my ($graphs,$mop) = eval {...}` | → `Pipeline->run`. Span 159–167 = 9 lines |
| ″ | 161 | `$graphs->{'main::corpus_case'}` | different entry name — confirms selector is a param |
| ″ | 166 | `lower($ret, mop => ...)` — **no** `program_mode` | must stay absent; `_tag_expected` at :198 consumes the `Int:`/`Str:` epilogue |
| ″ | 125 | header: *"cloned shape from son-corpus-wide.t run_through_bson"* | the file documents that it is a clone |
| `t/lib/.../Phase5LibCoverage.pm` | 71 | `from_json`; sets `stage = LOAD_FAIL` on failure | needs load and lower results SEPARATELY |
| ″ | 79–98 | unit selection: MOP methods filtered by `own_pkg` + free subs | **HARDEST CONSTRAINT** — stays in the harness |
| ″ | 108–122 | per-unit lower loop; does NOT abort on first failure | forces `run()` to return a LIST of per-unit results |
| `t/bootstrap/corpus/son-corpus-wide.t` | 60–119 | `run_through_bson` — **the 4th assembler, and the gate itself** | :78 from_json, :88 lower w/ `program_mode`, :322 asserts `>= 218` |
| ″ | 90 | `(defined $mop ? (mop => $mop) : ())` | **[VERIFIER ADDITION]** second conditional-spread site |
| `t/bootstrap/corpus/son-e2e.t` | 66 | **[VERIFIER CORRECTION] the FIFTH assembler.** `sub run_through_bson ($source)` — same name as son-corpus-wide.t's | :88–90 from_json, :93 `main::corpus_case`, :96 `returns->[0]`, :99–101 lower w/ mop and NO `program_mode`, :105–112 lli. 253 lines, live assertions :224/:230 |

### Blast radius (numbers)

- **Assemblers to migrate: 5** (plan says 3, measurement said 4).
- **Consumers of ProgramRunner: 8 call sites.** `grep -rln ProgramRunner t` returns 13 files; 5 are comment-only mentions (`llvm-arm-die-after-effect.t:33`, `reader-accessor-is-typed.t:30`, `son-corpus-wide.t:115`, and two more). **[VERIFIER NOTE]** the 13→8 filter is defensible but was undisclosed; the criterion is *`use`/call site, not comment*.
- **Test files affected: 6** — `program-runner.t`, `executable-gate.t`, `mode2-adapter.t`, `phase5-lib-coverage.t`, `son-corpus-wide.t`, `son-e2e.t`. Plus `loader-reproduces-the-wire.t` as the acceptance metric (unchanged by 4c).
- **Deleted-from-callers: ~65 lines.** **[VERIFIER CORRECTION]** measurement said 51; it omitted son-e2e.t:88–101 (14 lines). Verified spans: ProgramRunner 199–210 = 12; Mode2Adapter 159–167 = 9; Phase5LibCoverage 71 + 108–122 = 16; son-corpus-wide.t 78–91 = 14; son-e2e.t 88–101 = 14.
- **New file: ~120 lines.** **UNVERIFIED** — this is an estimate; a file that does not exist cannot be measured. The measurement's "MEASURED, not estimated" banner does not cover it.
- **`lib/` files changed: 0.**
- 17 other `t/bootstrap/*.t` files do `from_json`+`lower` inline. They are single-purpose unit tests, out of scope. **UNVERIFIED for ~13 of them** — the verifier spot-checked three and refuted the classification for son-e2e.t; the remainder were not individually checked.

### TDD build steps

**Step 1 — the per-unit contract.** Phase5LibCoverage is the hardest constraint; a shape satisfying it satisfies the others as the N=1 case.

- *Failing test first:* NEW `t/bootstrap/codegen-harness/pipeline.t`. Build a two-sub program via B::SoN, call `Chalk::CodeGen::Pipeline->new->run(json => $json, select => sub {...})`, assert the result is an arrayref of 2 hashrefs with keys `label`/`ok`/`ll`/`err`, and that a unit whose lowering dies yields `ok => false` **without aborting the second unit**. RED: `Can't locate Chalk/CodeGen/Pipeline.pm`.
- *Green:* create `t/lib/Chalk/CodeGen/Pipeline.pm`. `run($json, $select, %lower_opts)` — **`lower_opts` on `run()`, not the constructor** (C6). Loads; on failure returns `{stage=>'LOAD_FAIL', err=>$@, units=>[]}`; else `$select->(...)` returns `[[label,$ret],...]`; loop lowering each, accumulating per-unit hashes **without early return**.
- *The mop-extraction seam:* whatever line reads the MOP out of the load result gets a `# ponytail:` comment naming it as the single site 4d step 4 edits. That is the entire point of 4c-before-4d.
- *Verify:* `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib -It/lib t/bootstrap/codegen-harness/pipeline.t`

**Step 2 — migrate Phase5LibCoverage** (hardest caller first, so the shape is proven not retro-fitted).

- *Failing test first:* `t/bootstrap/phase5-lib-coverage.t`. Record current diag (`by_stage`, `own`, `lowered`, `gap_hist`) as baseline BEFORE editing.
- *Green:* replace :71 and :108–122 with one `Pipeline->run` whose `$select` closure contains existing lines 79–98 verbatim. Map returned units back onto `%res`. Keep `_clean` and the gap bucketing at :118–119 in the harness — report formatting, not pipeline.
- *Verify:* diff against baseline. **UNVERIFIED whether byte-for-byte diff is a valid gate** — `Phase5LibCoverage.pm:61` writes to a PID-derived path (`/tmp/p5lib_$$.err`) and :62–63 fold producer stderr into `$res{gaps}`; diag-stream determinism was not confirmed. Compare the four named scalars, not the whole stream, unless determinism is established first.

**Step 3 — migrate ProgramRunner** (N=1 with `program_mode`).

- *Failing test first:* `t/bootstrap/corpus/program-runner.t` and `t/bootstrap/corpus/executable-gate.t`. Record executable-gate.t's baseline. **UNVERIFIED that it emits a scored PASS count** rather than plain ok/not-ok — the verifier did not run it. Check before relying on "PASS count must not drop" as the signal.
- *Green:* replace :199–210 with `Pipeline->new->run($json, $select, program_mode => 1)`. Preserve the two distinct error strings at :202 and :204. Leave :137 alone.
- *Verify:* both test files.

**Step 4 — migrate Mode2Adapter** (N=1 with `program_mode` DELIBERATELY ABSENT).

- *Failing test first:* `t/bootstrap/corpus/mode2-adapter.t`, conformance `{pass,total,pct}` as baseline. A pipeline defaulting `program_mode` on shows here as pass → 0.
- *Green:* replace :159–167. No `program_mode`. Add a `# ponytail:` comment naming WHY it is absent (the epilogue is this harness's oracle, `_tag_expected` at :198), so a future unifier does not helpfully add it.
- *Verify:* conformance must match baseline exactly.

**Step 5 — migrate son-e2e.t.** **[NEW — VERIFIER-DISCOVERED, absent from the measurement's build steps]**

- *Failing test first:* `t/bootstrap/corpus/son-e2e.t` — live assertions at :224 and :230.
- *Green:* replace :88–101. Twin of Mode2Adapter: same `main::corpus_case` entry, same absent `program_mode`, same type-tagged oracle at :115. Nearly free once step 4 lands.
- *Verify:* run son-e2e.t.

**Step 6 — migrate son-corpus-wide.t `run_through_bson`.** Gate-affecting; coordinator runs it.

- *Failing test first:* the gate itself, floor at :322 (`>= 218`).
- *Green:* replace :78–91 with `Pipeline->new->run($json, $select, program_mode => 1)`. Keep the separate-stderr lli capture at :93–119 in the test — oracle plumbing, not pipeline.
- *Verify:* coordinator runs the ~10-minute gate; `gate_green >= 218`.

**Step 7 — prove the seam without building T1.**

- *Failing test first:* add to pipeline.t: pass `transforms => [ sub ($g) { $seen++; return $g } ]` and assert `$seen` equals the graph count and the lowered output is byte-identical to the no-transform run.
- *Green:* `field $transforms :param = [];` and thread the list **per graph** (C1). Two lines. That is the whole T1/T2/Optimizers accommodation.

### What is UNVERIFIED in 4c

- The ~120-line size of the unwritten `Pipeline.pm`.
- Whether `phase5-lib-coverage.t`'s diag output is deterministic enough for a byte-for-byte baseline diff.
- Whether `executable-gate.t` emits a scored PASS count.
- The "out of scope" classification of ~13 of the 17 non-harness `from_json`+`lower` files.
- Whether the graph-set shape at a pipeline seam violates spec §2 or is permitted by spec §11's deferral. Both readings are defensible; C1's resolution sidesteps the question rather than answering it.

---

## 4d — the MOP rides on the IR

**Verdict: NEEDS_REWORK on arithmetic, SOUND on substance. The strongest of the five.** Its step 1 was **empirically proven gate-neutral** by the verifier — see below.

### Blocking issues

**None.** The review's 4d finding is IMPORTANT, not BLOCKING: absorb the verifier's corrections into the edit surface before building.

### The empirical result that de-risks step 1

**[VERIFIER EXPERIMENT — carry this forward as step 1's committed safety argument]**

The verifier copied `lib/` to scratch (`lib/` and `t/` untouched; `git status --porcelain lib/ t/` clean throughout), dissolved the `:197` classes guard there, and fingerprinted every node's `(graph, id, operation, representation)` across all 218 corpus cases, HEAD vs dissolved:

- stamps **BYTE-IDENTICAL on all 218** (diff of the fingerprint column: no output)
- MOP transitions: **186 undef→def, 32 def→def, zero regressions**
- zero new `from_json` failures
- backend: on a class-less program the main-only sealed MOP yields a registry with **0 keys**, and `lower($ret, program_mode=>1, mop=>$mop)` vs `lower($ret, program_mode=>1)` produce **byte-identical LLVM IR (4083 bytes each)**

The measurement flagged gate-neutrality as *"MUST BE ASSERTED EXPLICITLY, NOT ASSUMED."* It is now proven.

### Blockers — true today?

| Requirement | True today | Evidence |
|---|---|---|
| Call node has a `target` field holding a MOP handle | **true** | `Node/Call.pm:35` `field $target :param :reader = undef;` under the comment spec §6 quotes verbatim |
| The target is actually POPULATED | **true** | two writers: `Bootstrap/Perl/Actions.pm:845`, `IR/Analysis.pm:499`. Ran `call-node-resolved-handle.t` → 7/7 |
| The call edge is TRAVERSED to reach the callee's graph | **true** | `Analysis.pm:597` `my $callee = $node->target->graph;`. Ran `call-target-is-a-metaobject.t` → 5/5 incl. *"target->graph IS the loaded callee graph, not a copy"* |
| A Graph can carry a MOP | **FALSE** | `Graph.pm` has exactly 5 fields; no mop, no setter. **The one genuinely missing piece** |
| A MOP exists for every loaded program | **FALSE** | `Analysis.pm:197` gates all MOP construction behind a classes check |
| `Call.target` populated for every program | **FALSE** | `_attach_call_targets` invoked only at :220, inside the guard |
| Method-dispatch Calls reach callee through the edge | **FALSE** | `:487-490` filters `eq 'direct'`; `_stamp_method_call_reprs` resolves by class-name string |
| A MOP-carrying Graph survives round-trip | **FALSE** | `to_json` at `:430` emits only `{version, source, methods}` |
| The MOP could be built BEFORE the inference passes | **FALSE** | three passes MUTATE raw `$classes` before seal; `MOP/Field.pm:15` has no type setter; `MOP.pm:22-25` seal is one-way. **Ordering is structurally forced** |
| `_build_registry_from_mop` is a redundant copy | **FALSE** | derives six classes of fact the MOP does not hold — see plan corrections |

**The classes guard is the real blocker, and it is bigger than estimated.** Measured over the gate's own corpus using the gate's own producer invocation: **218 considered cases (22 corpus-declared GAPs excluded), 186 load with `$mop` UNDEF = 85.3%.** Only `classes.md` (18) and `subs.md` (12) plus 2 strays produce a MOP. Spec §2's inter-unit edge does not exist for the majority of the corpus.

**[VERIFIER NOTE on method]** the producer invocation matters: `son-corpus-wide.t:63-66` uses an INCLUDE list (`package=main`, `package=<class>`), `ProgramRunner.pm:182` uses an EXCLUDE list. Running without either returns ~100 B::SoN-internal classes for EVERY program, which would have inverted the headline blocker.

### Verified edit surface

| File | Line | What is there now | What must change |
|---|---|---|---|
| `lib/Chalk/IR/Analysis.pm` | 302 | `return (\%graphs, $mop);` | → `return \%graphs;` — but only after the MOP has a home on each Graph |
| ″ | 300–301 | comment: *"$mop is returned only in list context"* | **FALSE OF ITS OWN FUNCTION** — `run()` returns a 2-list unconditionally. Stale, copy-pasted from `from_json` in commit f92c6869 |
| ″ | 196 | `my $mop;` then `:197` `if (ref $data->{classes} eq 'HASH' && %{...}) {` | **THE LOAD-BEARING EDIT.** Guard must dissolve. `MOP.pm:30-32` already seeds an implicit `main`. The plan does not mention this at all |
| ″ | 205 | `_seed_and_propagate_reprs(\%graphs);` — **INSIDE the guard** | **[VERIFIER ADDITION]** dissolving newly runs whole-program repr propagation for 186 cases, as an extra propagation before the unguarded one at :226. Omitted from the measurement's enumeration |
| ″ | 213 | `$mop = _replay_classes($classes, \%graphs);` | must run unconditionally |
| ″ | 220 | `_attach_call_targets(\%graphs, $mop);` | must run unconditionally — sole writer of `Call.target` on the B::SoN path |
| ″ | 238 | `while (_stamp_method_call_reprs($data->{classes} // {}, \%graphs) > 0)` | **[VERIFIER ADDITION]** ALREADY unguarded, already receives `{}` for class-less programs — **the strongest existing precedent for step 1's safety**, uncited by the measurement |
| ″ | 826–853 | `_infer_param_field_types` calls `_ctor_arg_reprs($graphs)` as its FIRST statement, which walks every node of every graph | **[VERIFIER CORRECTION]** the measurement claimed the field-inference passes are `keys %$classes` loops. Two of three are not. They still return 0 on empty `$classes` — **the conclusion holds, the stated reason does not** |
| ″ | 1427–1467 | `_infer_field_types_from_stores` opens with a BFS over every graph at :1434; reaches `keys %$classes` only at :1459 | same correction |
| ″ | 487–490 | `_attach_call_targets` filters `eq 'direct'` | widen to `'method'`, resolving through `$mop->for_class($node->class_name)` |
| ″ | 1626–1642 | `_stamp_method_call_reprs` resolves by string: `$classes->{$c}{parent}` walk, indexing `%ret_repr` built at :1576–1612 from `$graphs->{...}` | must read `$node->target->return_type`. **Unscheduled in the plan** |
| ″ | 1598–1605 | wire-vs-graph return-type disagreement `die` | **[VERIFIER ADDITION]** load-bearing; must NOT be deleted in step 3's move. Also see B3 |
| `lib/Chalk/IR/Serialize/JSON.pm` | 707 | `my ($analysed,$mop) = Chalk::IR::Analysis->run(...)` | → single value. **The ONLY `lib/` consumer** |
| ″ | 710 | `return ($analysed,$mop) if wantarray && defined $mop;` | **THIS, not :302, is what the 27 test sites couple to.** Context- AND value-sensitive: a class-less wire silently hands `$m = undef` |
| ″ | 430 | `sub to_json ($named_graphs)` emits no `classes` key | hard CONSTRAINT: a graph-carried MOP does not round-trip |
| `lib/Chalk/IR/Graph.pm` | 13 | 5 fields: `$start_param`, `$returns_param`, `$schedule`, `%cache`, `$cfg_counter` | add `field $mop :param :reader = undef;` + `method set_mop($m)`. **A setter is REQUIRED** — the MOP is sealed after graphs exist. ~6 lines |
| `lib/Chalk/Target/LLVM.pm` | 1078 | `defined $opts{mop} ? _build_registry_from_mop($opts{mop}) : {}` | **NOTHING for 4d.** `lower()` takes a RETURN NODE (`:53`), and `Chalk::IR::Node` has no graph field |
| `t/lib/.../ProgramRunner.pm` | 207 | `(defined $mop ? (mop => $mop) : ())` | **[VERIFIER ADDITION]** the actual behavioural coupling of step 1 — where "a MOP always exists" changes what the BACKEND receives for 186 cases |
| `t/bootstrap/corpus/son-corpus-wide.t` | 90 | same conditional spread | **[VERIFIER ADDITION]** same |

### Blast radius (numbers)

- **Two-value return consumers: 27 call sites across 25 files, ALL under `t/`, ZERO in `lib/`.** Command: `grep -rnE '\( *(undef|\$[A-Za-z_]+) *, *\$[A-Za-z_]+ *\) *= *(eval *\{ *)?(Chalk::IR::Serialize::JSON::)?from_json' --include='*.pm' --include='*.t' lib t | grep -v Serialize/JSON.pm`
- **`lib/` consumers of `Analysis->run`: 1** (`Serialize/JSON.pm:707`).
- **Silent-survivor one-value-LIST sites: 3** — **[VERIFIER CORRECTION]**, measurement said 2. `ir-serialize-json.t:238` (`my ($g1) = from_json($loop_json);`), `ir/lowerable-stamp-admission.t:47`, `ir/loader-reproduces-the-wire.t:123`. **These keep working silently through any change to the second return value. Re-read all three by hand; do not trust them to fail.** The undercount defeats the warning's own purpose.
- **Scalar-context sites: 33 across 13 files** — **[VERIFIER CORRECTION]**, measurement said "32 in `ir-serialize-json.t`". That file has 9. Distribution: `ir-serialize-json.t` 9, `ir-subclass-field-audit.t` 9, `ir-node-unify-roundtrip.t` 3, `son-aggregate-repr.t` 3, and 9 files with 1 each.
- **`mop => $mop` lowering axis: 48 lines across 23 files** — **[VERIFIER CORRECTION]**, measurement said 50. Not touched by 4d.
- **Pass invocations in `run()`: 17, distinct names 11** — both CONFIRMED, matching the spec. **Subs in the file: 26** — **[VERIFIER CORRECTION]**, measurement said 25.
- **Estimated lines: ~140.** **UNVERIFIED** — the 27 call sites are measured; the 6/25/4/50 components are forward-looking estimates of unwritten code.
- Not counted: moving method dispatch onto the edge (`:487`, `:1626`), which the plan does not schedule and which is comparable in size again.

### TDD build steps

**Step 0 — pin the edge that already exists.** 4d's headline is already true for direct dispatch; lock it, and establish RED against the real blocker.

- *Failing test first:* NEW `t/bootstrap/mop/mop-rides-on-the-graph.t` subtest 1 — load `my $x=0; for my $i (1..3) { $x += $i } print $x;` through `from_json` in LIST context, assert the second return value is defined. RED today: the producer emits `classes: undef`, so `:197` skips and `:710`'s `wantarray && defined $mop` returns a 1-element list.
- *Green:* none. This establishes RED only.
- *Verify:* new subtest fails; `call-target-is-a-metaobject.t` still 5/5, `call-node-resolved-handle.t` still 7/7. Do NOT run the corpus gate.

**Step 1 — a MOP always exists.** Dissolve the `:197` guard.

- *Failing test first:* subtest 1 goes green. ADD subtest 2: on the same program, `$mop->for_class('main')` is defined and `$mop->is_sealed` is true.
- *Green:* replace `:196-222`'s guarded block with `my $classes = (ref $data->{classes} eq 'HASH') ? $data->{classes} : {};` and the same body unguarded. Then delete `&& defined $mop` from `Serialize/JSON.pm:710`.
- *Safety argument (corrected):* the field-inference passes return 0 on empty `$classes` **because their write loops are classes-keyed** — NOT because the passes do not run. `_infer_param_field_types` and `_infer_field_types_from_stores` both walk every graph first. `:205`'s `_seed_and_propagate_reprs` newly runs for 186 cases. Precedent: `:238`'s `_stamp_method_call_reprs` is already unguarded and already receives `{}`.
- *Verify:* **coordinator runs the full gate.** Expect 218 — and expect it, because the verifier's scratch experiment produced byte-identical stamps on all 218 and byte-identical LLVM IR. Also run `t/bootstrap/mop/*.t` and the three `(undef, $mop)` sites (`mop/sub-replay.t:28`, `ir/son-classes-replay.t:60`, `loader-return-type.t:32`), which move from "undef because no classes" to "defined main-only MOP". The registry-equivalence (`_build_registry_from_mop` skips `main` at `LLVM.pm:350`, so a main-only MOP yields an EMPTY registry identical to the `: {}` branch) is now proven, not assumed.

**Step 2 — give Graph a mop field and attach it.** Purely additive; nothing reads it yet.

- *Failing test first:* subtest 3 — for every graph from `from_json`, `$g->mop` is defined and is the SAME object (`refaddr`) as the second return value. RED: no such field.
- *Green:* `Graph.pm`: `field $mop :param :reader = undef;` + `method set_mop($m)`. In `Analysis.pm` after `_replay_classes` returns: `$_->set_mop($mop) for values %graphs;`. ~6 lines.
- *Verify:* `ir-node-unify-roundtrip.t` and `ir-serialize-json.t`. **The new invariant must NOT be asserted on a `to_json`-reloaded graph** — `to_json` at `:430` drops it. Gate run optional; the change is additive and unread.

**Step 3 — move method dispatch onto the edge.** This is what actually makes spec §2 true, and the plan does not contain it.

- *Failing test first:* subtest 4 — `class Base { method m { 7 } } class Child :isa(Base) {} Child->new->m`; find the method-dispatch Call, assert `$call->target` is a `Chalk::MOP::Method`. RED: `:487-490` filters `eq 'direct'`.
- *Green:* (a) widen `_attach_call_targets` to `'method'`, resolving via `$mop->for_class($node->class_name)` and the MOP's parent chain. **UNVERIFIED that `Chalk::MOP::Class` exposes a usable parent/MRO traversal** equivalent to the raw-hash walk — no MOP::Class method was cited by either agent. Check this before building. (b) rewrite `_stamp_method_call_reprs` to read `$node->target->return_type`. **KEEP the wire-vs-graph reconciliation at `:1598-1605`** — it refuses loudly on disagreement and is load-bearing.
- *Verify:* full gate (second high-risk step). Also `whole-program-method-call.t`, `void-method-chain.t`, `ir/method-return-type-from-wire.t`, `ir/reader-accessor-is-typed.t`.
- **OPEN DISAGREEMENT:** the measurement asserts "if the gate drops, revert THIS STEP ONLY — steps 1 and 2 stay landed." The verifier notes step 3 rewrites resolution inside the `:238` fixpoint that step 1 newly feeds with a main-only MOP, and the independence is asserted, not demonstrated. **What settles it:** before landing step 3, revert-test it in scratch — land 1+2+3, revert 3 alone, confirm the gate returns to its post-step-2 value.

**Step 4 — collapse the return shape.** The 27-site edit; most resembles the change that took the gate 218 → 136.

- *Failing test first:* subtest 5 — `scalar(() = from_json($json))` == 1 for both class-bearing and class-less programs. RED while `:710` returns a 2-list.
- *Green:* `Analysis.pm:302` → `return \%graphs;`; `Serialize/JSON.pm:707` single-value; delete `:710`'s wantarray line. Then the 27 call sites: `my $graphs = from_json($json); my $mop = (values %$graphs)[0]->mop;`. The three `(undef,$mop)` sites need the graphs anyway. `ir/method-return-type-from-wire.t:59` needs care — the only predeclared-assign form, inside a `lives {}` block.
- *Verify:* full gate at 218, plus the 25 affected files individually. **Hand-re-read all THREE one-value-LIST sites** (`ir-serialize-json.t:238`, `lowerable-stamp-admission.t:47`, `loader-reproduces-the-wire.t:123`). **Land ONLY after 4c has migrated all five assemblers** — the simultaneity is what broke on 2026-08-25 (C5).

**Step 5 — do not delete `_build_registry_from_mop`.** Correct the plan instead. No code change, no gate run. See "Plan corrections needed".

### What is UNVERIFIED in 4d

- The ~140-line estimate's component breakdown.
- Whether `Chalk::MOP::Class` exposes a parent/MRO traversal usable by step 3.
- Whether step 3 is genuinely revert-independent of steps 1–2 (see OPEN DISAGREEMENT above).
- The causal claim that the 2026-08-25 218→136 incident was the three-harness simultaneity, sourced to `plan:1018`, whose line number was not re-verified against HEAD.
- "roughly 85% of corpus cases" was derived by arithmetic on filenames in the measurement; the verifier measured it directly at 85.3% (186/218), so the number is right but was not established by the evidence originally given.

---

## 4a — the total join

**Verdict: NEEDS_REWORK. Split it. Steps 1–3 build; step 4 is parked.**

### BLOCKING — B2: step 4 breaks an acceptance criterion with no available remedy

Deleting the Undef drop moves L3b, L3c, L3d from GREEN to GAP — gate **218 → 215**. Spec §227: *"The corpus gate holds at 218 as a floor."* The measurement's own step 4 says: *"There is no third option that keeps them green."* Option (a) (lower the floor) is not available under the spec. Option (b) requires T2, which no sub-slice 4a–4e builds.

**Resolution: split 4a.** Steps 1–3 are measured corpus-inert and land in position. Step 4 is parked behind T2 with a filed follow-up, or requires an explicit coordinator/spec amendment to §9.5 before scheduling. **It must not block the 4b/4e chain.**

### BLOCKING — B3: precision regression and unanalyzed blast radius

Three separate defects, none visible to the measurement's simulation:

1. **Fixpoint freezing.** `Analysis.pm:1148` is `next if _is_narrowed($node->representation);` at the TOP of the propagation loop containing the join. `_is_narrowed` (`:448-450`) is `defined $repr && $repr ne 'Unknown'` — so `'Scalar'` IS narrowed. Today an undominated merge returns undef, stays unstamped, and every later `while ($changed)` iteration reconsiders it as inputs improve. After 4a it is stamped Scalar on pass 1 and **permanently skipped**. That is widening without a merge requiring it — forbidden by spec §3 and §9.3.
2. **The second `_element_repr` caller.** `Analysis.pm:1510` (`my $er = _element_repr($default);`) feeds `%field_elem_type`, consumed at `:1541-1548` to stamp Subscript nodes reading out of aggregate FIELDS. Under a total join the `if defined $er` guard at `:1511` admits entries it never had. The simulation covered only the `:1266` merge loop, so **"exactly 3 movers" and step 4's revert criterion are miscalibrated.**
3. **A `die` inside `lib/IR`.** `Analysis.pm:1598-1605` dies when a graph-derived return repr disagrees with the wire's, guarded by `next unless _is_narrowed($repr);` at `:1601`. HEAD's undef repr skips it; a Scalar repr does not. **This falsifies the blocker "every Scalar refusal is in Target/"** on which the entire "GAP not crash" safety argument rests.

**Before building 4a:** re-run the simulation instrumenting BOTH `_element_repr` callers and counting nodes frozen-by-first-Scalar across fixpoint iterations. Decide whether the join result should be withheld until the fixpoint stabilizes, or `_is_narrowed` taught that Scalar is refinable. Add a test for the `:1601` die with a Scalar-joined return vs a narrower wire stamp.

### BLOCKING — B4: the FOURTH improvisation has no owner, and there are FOUR sites

The plan (lines ~878–884) names FOUR improvisations. Every measurement analyzed three. The fourth is the backend's `$repr // 'Int'` defaults, *"which guess when the loader supplied nothing."*

**[REVIEW MEASUREMENT at HEAD]** `grep -rn "// 'Int'" lib/Chalk/Target/LLVM/Context.pm`:

| Line | Code |
|---|---|
| 3349 | `my $phi_repr = (($repr // 'Int') eq 'Slot') ? 'Int' : ($repr // 'Int');` |
| 4071 | `$self->{_vd_repr}{$vd_id} // 'Int'` |
| 5801 | `$node->representation // 'Int'` |
| 6827 | `$minfo->{return_repr} // 'Int'` |

`:3349` sits **inside the DefinedOr phi path L3b/L3c/L3d lower through** — the exact cases step 4 changes. Slice 4 deletes the loader improvisations that compensated for missing reprs while leaving the backend guess in place. Per spec §1 a silent Int guess is **the only unacceptable outcome**. This is the shape of a shipped miscompile.

**Fix:** assign an owner. Minimum for slice 4: convert each `// 'Int'` into a loud GAP die in the same arc that makes the join total, since a total join makes "repr absent at the backend" near-impossible and the default then only fires on a bug. Measure which corpus cases hit each site before converting.

### Blockers — true today?

| Requirement | True today | Evidence |
|---|---|---|
| `join_types` is a total LCA | **true** | RAN IT. `(Undef,Int)=Scalar`, `(Int,Str)=Str`, `(ArrayRef,Int)=Scalar`, `(Array,Int)=List`, `(Unknown,Int)=Unknown`, `(Slot,Int)=Unknown`, `(Boolean,Int)=Str`, `(None,Int)=Int`, `(Slot,Slot)=Slot`. All four plan predictions confirmed exactly. `TypeLibrary.pm:298-322` |
| `join_types` reachable from Analysis.pm | **true** | `:14` already `use`s TypeLibrary; `:1022` calls `is_subtype` fully-qualified |
| Every Scalar refusal is in `Target/` | **FALSE** | **[VERIFIER CORRECTION]** — 15 die-sites in `Target/LLVM/Context.pm`, but `Analysis.pm:1598-1605` dies on a Scalar-vs-wire disagreement inside `lib/IR` |
| The `'same'` rule is live | **FALSE** | `%_COMPUTED_REPR:110` reads `And => 'join', Or => 'join'`. No op maps to `'same'`. Dead since commit 6d9fc083, predating the plan |
| The Unknown drop is load-bearing | **FALSE** | Over 240 corpus cases: 94 `_join_repr` calls, **`calls_with_unknown_arm = 0`**. `%LOWERABLE_STAMP` (`Serialize/JSON.pm:71`, applied `:634`) omits `'Unknown'`, filtering every Unknown wire stamp to undef before inference. **UNVERIFIED as to exact counts** — no script preserved; the verifier independently confirmed the MECHANISM, making the zero-Unknown conclusion PLAUSIBLE |
| T2 exists for Scalar merges to lower | **FALSE** | `%_REPR_NO_MACHINE_TYPE{Scalar}` at `Context.pm:3646-3651`; `_repr_to_llvm_type` at `:3676-3682` dies |
| The three corpus ir-blocks do not pin the changing stamps | **FALSE — they do** | `logical.md:180` (L3b), `logical.md:1053` (L3d), L3c's Region-Phi. Shape checker `MdtestCorpus.pm:1686-1690` fails a defined-but-different repr |

### Verified edit surface

| File | Line | What is there now | What must change |
|---|---|---|---|
| `lib/Chalk/IR/Analysis.pm` | 1004 | `sub _join_repr (@reprs)`, 1004–1026. Empty guard, Unknown drop (1017–18), dominating-arm `is_subtype` loop (1020–24), `return undef` (1025) | body → total fold: `my $acc; $acc = TypeLibrary::join_types($acc,$_) for @reprs; return $acc;`. Keep `return undef unless @reprs;` (1 line, documents the contract). 23 lines → ~4 |
| ″ | 988 | `_join_repr` doc comment begins | **[VERIFIER CORRECTION]** measurement said :985. Rewrite — it documents the rank-table lineage and two exclusions that no longer apply |
| ″ | 1007–1018 | IMPROVISATION 1 — Unknown drop + 10-line comment. Its `(:1548)` cross-ref is STALE | DELETE. `join_types` absorbs natively (spec §10). **Measured consequence: ZERO** |
| ″ | 1228–1241 | IMPROVISATION 2 — Undef drop + 12-line comment, in caller 1 | DELETE. **THE ONLY IMPROVISATION WITH MEASURABLE BEHAVIOUR CHANGE.** Parked — see B2 |
| ″ | 1218–1226 | IMPROVISATION 3 — `'same'` uniqueness bail; guard at `:1192` | DELETE as DEAD CODE. Zero behaviour change |
| ″ | 1266 | CALLER 1: `my $widest = _join_repr(@reprs); next unless defined $widest;` | mechanically unchanged — but see B3 defect 1. The 26-line Slot-arm comment at 1243–1265 stays; its reasoning survives (`join_types(Slot,Int)=Unknown`) |
| ″ | 1148 | `next if _is_narrowed($node->representation);` — fixpoint entry guard | **[VERIFIER ADDITION]** B3 defect 1. `_is_narrowed` at `:448-450` |
| ″ | 1342 | CALLER 2: `return _join_repr(@reprs);` — tail of `_element_repr`. No Undef/Unknown drop guards it | latent exposure: `elems(Int,Undef)` today undef → total Scalar. **Measured corpus impact: zero** (no literal aggregate with an undef element) |
| ″ | 1510 | `my $er = _element_repr($default);` — **the THIRD/second-caller path** | **[VERIFIER ADDITION]** B3 defect 2. Feeds `%field_elem_type` |
| ″ | 1541–1548 | consumer of `%field_elem_type`, stamps field-Subscript nodes | **[VERIFIER ADDITION]** newly stamped under a total join |
| ″ | 1598–1605 | wire-vs-graph disagreement `die` | **[VERIFIER ADDITION]** B3 defect 3 |
| ″ | 14 | `use Chalk::Grammar::Perl::TypeLibrary;   # is_subtype / join_types: the lattice` | no edit. Note: this comment is the ONLY `join_types` reference in `lib/` outside its own definition — **the plan's "implemented, correct, and unused" is CONFIRMED** |
| `lib/Chalk/Target/LLVM/Context.pm` | 3349, 4071, 5801, 6827 | `$repr // 'Int'` | **B4 — no owner today** |
| `t/bootstrap/join-drops-unknown.t` | 36–43 | 56 lines asserting DROP: `_join_repr('Int','Unknown') eq 'Int'` (:37), reverse arms (:40), `('Int','Str') eq 'Str'` (:43), all-Unknown (:51). VERIFIED PASSING | **MUST BE REWRITTEN, not updated** — it is the direct anti-contract of spec §10. `:43` and `:51` survive unchanged. **[VERIFIER NOTE]** the measurement enumerated only 37/40/51 while calling the file fully characterized |

### Blast radius (numbers)

- **`_join_repr` sites: 3** — defn `:1004`, callers `:1266` and `:1342`. Grep across `lib/` and `t/` returns `Analysis.pm` plus two test files.
- **`_element_repr` call sites: 2** — `:1170` (Subscript over literal aggregate) and `:1510` (field default). **[VERIFIER CORRECTION]** — the measurement analyzed one.
- **Production deletions: ~54 lines net** — Unknown drop 12 (1007–1018), Undef drop 14 (1228–1241), `'same'` branch 9 (1218–1226), `_join_repr` body/comment ~19 replaced by ~4. **The plan's "MOSTLY SUBTRACTION" HOLDS for `lib/`** — the verifier read the ~54 lines and confirms they are comment-plus-guard removals, not load-bearing logic.
- **Corpus contract edits (step 4 only):** 3 one-token stamp edits in `logical.md` **plus their surrounding prose** — L3d's numbered point 2 at `md:1032-1035` states *"Undef contributes no value to widen, so it is dropped before the join"*, which becomes false. **The plan does not budget for the prose contradiction.**
- **Stamp movers under step 4: 3 of 176 merges** (L3b, L3c, L3d — all `Int -> Scalar`, all in `logical.md`). **UNVERIFIED and now SUSPECT** — no script preserved, and by construction the simulation could not observe the `:1510` path or the fixpoint freezing. **A revert criterion calibrated on this number will misfire.**
- **`_join_repr` call census: 94 calls over 240 cases, all homogeneous** (`Int,Int` ×50; `Int,Int,Int` ×25; `Int` ×9; `Str,Str` ×5; `Boolean,Boolean` ×2; `Num,Num` ×1; `Num` ×1; `Str` ×1). **UNVERIFIED** — mechanism confirmed, exact counts unreproducible.
- **Estimated lines: 75.**

### TDD build steps

**Step 1 — rewrite the Unknown contract test to assert absorb.**

- *Failing test first:* rewrite `t/bootstrap/join-drops-unknown.t` → `join-absorbs-unknown.t`: `_join_repr('Int','Unknown') eq 'Unknown'` and the reverse arm order. RED at HEAD (returns `'Int'` both ways — verified by probe). Keep `:43` (`Int,Str -> Str`) and `:51` (all-Unknown) as regression anchors. Rewrite the ABOUTME and the 25-line rationale comment, which argue FOR drop, and fix the stale `Serialize/JSON.pm:1548` reference.
- *Green:* delete `Analysis.pm:1007-1018`. Nothing else — the dominating-arm loop already returns Unknown for the all-Unknown case.
- *Verify:* run the test. Then re-run the 240-case instrumented probe: drop-vs-absorb disagreement count must still be 0, proving corpus-inertness. **Record in the commit that absorb is INERT until `%LOWERABLE_STAMP` (`Serialize/JSON.pm:71`) admits Unknown per spec §8** — otherwise a later reader will think this change did something.

**Step 2 — make `_join_repr` total.**

- *Failing test first:* new unit test: `_join_repr('Undef','Int') eq 'Scalar'`, `('ArrayRef','Int') eq 'Scalar'`, `('Array','Int') eq 'List'`, `('Boolean','Int') eq 'Str'`. All four RED at HEAD (all return undef — verified). **Pin `Boolean,Int -> Str` explicitly: the user has RULED this INTENDED**, so a later reader does not "fix" the lattice. Also pin `('Slot','Int') eq 'Unknown'` and `('Slot','Slot') eq 'Slot'` — the second is the short-circuit case the plan's Slot reasoning misses (`TypeLibrary.pm:301` `return $left if $left eq $right;` precedes absorption at `:309`). **Add `('Slot','Unknown')`** — **[VERIFIER ADDITION]** HEAD returns `'Slot'`, total returns `'Unknown'`; it is where drop-vs-absorb and Slot's non-membership interact.
- *Green:* replace `:1004-1026`'s body with the fold. Rewrite the `:988-1003` header comment.
- *Verify:* the new test. Then re-run the total-join simulation over 240 cases and confirm **ZERO stamp changes** — because the caller's Undef drop at `:1240` still runs ahead of it. That zero is the proof this step is isolated from step 4.
- **Also verify `t/bootstrap/ternary-joins-arms-only.t`.** **[VERIFIER CORRECTION — the measurement's stated RED is wrong in both directions]** The file contains **no Undef assertion** (`grep -c 'Undef'` → 0). Its three subtests pin `Boolean/Int/Int -> Int`, `Boolean/Int/Str -> Str`, `Boolean/None/Int -> Int`. `None` is the lattice BOTTOM (`TypeLibrary.pm:303-305`), not Undef; `join_types('None','Int')='Int'`, so subtest 3 stays GREEN. **The real hazard: `join_types('Boolean','Int','Int')='Str'`, so subtest 1 is kept green ONLY by the TernaryExpr condition-drop at `Analysis.pm:1214` (`@in = @in[1..$#in] if $op eq 'TernaryExpr' && @in > 1;`).** Fold over the raw input list and subtest 1 flips Int→Str. **Preserve `:1214`.**

**Step 3 — delete the dead `'same'` branch.**

- *Failing test first:* **NO RED TEST EXISTS OR CAN EXIST** — the branch is unreachable. Per the project's TDD rule, a test that cannot fail is not a test. The honest verification is a coverage assertion: a one-line check that `grep { $_ eq 'same' } values %_COMPUTED_REPR` is empty, which goes RED if someone re-introduces the rule.
- *Green:* delete `:1218-1226`; change `:1192` to `if ($rule ne 'join') {`.
- *Verify:* full `t/bootstrap/*.t` + `t/bootstrap/ir/*.t`. Zero outcome diff. **Commit SEPARATELY** so any later gate movement is unambiguously attributable.

**Step 4 — PARKED (B2).** Delete the Undef drop. Do not schedule inside slice 4.

When it is scheduled (behind T2, or behind an explicit §9.5 amendment):

- *Failing test first:* build `DefinedOr(Constant(undef):Undef, Constant(9):Int)` through `_seed_and_propagate_reprs`, assert `'Scalar'`. RED at HEAD (`'Int'`). **Pair bilaterally** with `DefinedOr(Int,Int) -> 'Int'` — otherwise the test passes against a join returning Scalar for everything.
- *Green:* delete `:1228-1241`. Update the three corpus contracts **in the same commit**: `logical.md:180`, `logical.md:1053`, L3c's Region-Phi; and rewrite the prose at `md:1032-1035`.
- *Verify:* **NOT `logical.t`.** **[VERIFIER CORRECTION — the measurement's named verification is vacuous]** `t/bootstrap/corpus/logical.t:26-36` states: *"the old per-case run_case checks here lowered the hand-written IR BLOCK… Retired in favor of the single authoritative gate; the presence/declaration checks below lower nothing and stay."* Its `ok N — declared L: GREEN` assertions confirm the markdown contains the string `L: GREEN`. **It passes identically before and after, and keeps passing if all three cases stop lowering.** Verify via `son-corpus-wide.t` (coordinator) plus a new unit test that actually lowers a `DefinedOr(Undef,Int)`.
- *Revert criterion:* **do not use "exactly 3 movers"** until the simulation is re-run instrumenting both `_element_repr` callers and the fixpoint guard (B3).

### What is UNVERIFIED in 4a

- The 94-call census and the post-load repr census (mechanism confirmed, exact counts unreproducible).
- "176 merge nodes examined, exactly 3 change" — and now **suspect**, since the simulation's scope excluded `:1510` and the fixpoint interaction.
- "no literal aggregate with an undef element" — the grep is unquoted, and it tests only the literal path, not the field-default path at `:1510`.
- The claim that `join_types` is referenced exactly once outside TypeLibrary.pm across all of `lib/` (spot-confirmed at `:14`, exhaustive count not reproduced).

---

## 4b — the edge analyses

**Verdict: NEEDS_REWORK. Re-scope before building (C2).**

### BLOCKING — B5: analysis (iii) widens a known silent-miscompile divergence

Making `_element_repr` store-aware changes typing while `DefinedOrFold::_element_at` continues constant-folding element READS from initializers, ignoring stores.

**[VERIFIER PROBE]** `my @arr=(1,2); $arr[0]=99; my $v=$arr[0]//5;` — the post-store Subscript (id `...|Assign#3`) resolves via `_resolve_aggregate` to `Constant(1)`, the INITIALIZER. `_element_at` uses that same resolution to constant-fold the read to that node. **Perl prints 99.**

The measurement's stated mitigation — *"Keep `_resolve_aggregate`/`_unwrap_ref` unchanged so DefinedOrFold's mirrored copy stays in sync"* — addresses the wrong risk. Sync is not the hazard; **store-blindness** is. And `DefinedOrFold.pm:104-109`'s own comment records that this divergence class produced a silent miscompile once already.

**Fix, in the same commit as (iii):** either make `_element_at` refuse (return "cannot fold") for any container with at least one store-consumer, or teach both copies store-awareness together. Add the store-then-defined-or case as a test proving `lli == perl == 99`.

### Re-scoping (C2) — what 4b actually builds

**Removed** (assigned to earlier slices, and green-on-arrival if left here):

- The `_join_repr` fold and the `'same'` deletion → 4a steps 1–3.
- The `_attach_call_targets` guard hoist and the empty-MOP seal → 4d step 1.

**4b's real content:**

| # | Analysis | State |
|---|---|---|
| (i) | `_resolve_direct_calls` reads the **edge** instead of the hash | still RED after 4d |
| (ii) | gather-then-stamp restructure of `_seed_direct_call_arg_reprs` | the only structural rework |
| (iii) | store-aware `_element_repr` + the DefinedOrFold fix (B5) | the only one both unblocked AND unbuilt |
| (iv) | no-tie grep assertion | an assertion, not an analysis |

### Blockers — true today?

| Requirement | True today | Evidence |
|---|---|---|
| 4a's total join exists | **false (until 4a lands)** | `grep -rn 'join_types' lib/` → definition + one comment. Zero call sites |
| (i) a Call carries a resolvable handle to its callee | **true** | probe: `CALL Call#2 in main::corpus_case name=main::f dk=direct target=Chalk::MOP::Sub target_graph=YES`. **Analysis (i) is DONE for the resolution half** — the work is reading the edge instead of the hash |
| (ii) a BACKWARD edge from callee to callsites exists | **false — and NOT NEEDED** | No back-edge on MOP::Sub or Graph. **But the callee is a SHARED SINGLETON**: both `Call#2` and `Call#4` to `main::f` return identical `target_refaddr`/`callee_graph_refaddr`, and that graph IS `$graphs{'main::f'}`. So the callsite set is gathered by ONE FORWARD SWEEP bucketing by `refaddr(target)`. Corroborated by `son-corpus-wide.t`'s own gate message: *"THE CALLEE GRAPH IS ONE OBJECT SHARED BY EVERY CALL SITE"* |
| (iii) every store into a container is reachable from the container | **true — two hops** | probe on `my @arr=(1,2); $arr[0]=7; $arr[1]="s";`: `ArrayRef#3` → 3 Subscript consumers → each lvalue Subscript's consumers contain the Assign. Consumer edges populated via `NodeFactory::_register_consumers` (`:182-196`); `Serialize/JSON.pm:605-608` routes all deserialization through the factory |
| (iv) the subset contains zero tie sites | **true** | **Independently re-measured at ZERO in BOTH repos.** chalk `lib/`: operator-form grep rc=1; 14 word-boundary hits all read and classified as English "tie-break"/"tie log"/"unresolved tie" in Semiring comments. perl5-son `lib/`: rc=1; 3 word hits are OpMap.pm:252-254 opcode-TABLE rows (`tie => ['mark','Call',1,0]`), declarations of how to translate tie, not uses |
| The exit condition has a non-zero baseline | **true — it is ELEVEN, not zero** | **[VERIFIER CORRECTION — the measurement's loudest finding is inverted]** |

**On the exit condition.** The measurement claimed *"THE COUNT IS ALREADY ZERO… vacuously satisfied… a builder will conclude 4b is unnecessary."* This splits "absent" from "Unknown" in exactly the way **spec §4 line 85 forbids**: *"Absence normalizes to Unknown on ENTRY. A Value node arriving without a stamp is TREATED AS Unknown; the only difference is whether some pass wrote the fact down."* Under the spec's own definition the metric is **absent + Unknown = 11 + 0 = ELEVEN**. The measurement's own data contains the refutation — it reports `absent=11` two lines after asserting zero.

The codebase independently records the same work as real: `Analysis.pm:314` *"Enabling it drops the corpus gate 218 → 200, with 18 cases failing"*; `:368-370` *"SIXTEEN → TEN untyped, THREE roots left (Call 2, Ref 1)"*; `:393` *"THIS IS A REAL GAP IN THE LOADER'S TYPING, not a bad assertion."* And `Analysis.pm:298` — `# _assert_value_nodes_are_typed(\%graphs);` — is **already commented out**, under the banner "THE EXIT INVARIANT — NOT YET ENFORCED". Spec §9.4's "an assertion that must be disabled to land" is already satisfied.

**Use `absent + Unknown` as the metric, and the 18-case cost of enabling the assert as the baseline.**

### Verified edit surface

| File | Line | What is there now | What must change |
|---|---|---|---|
| `lib/Chalk/IR/Analysis.pm` | 543 | `sub _resolve_direct_calls ($graphs)`, 25 lines. `my $callee = $graphs->{ $node->name } or next;` | **(i)** — the graph-set lookup spec §2 rejects. Read `$node->target->graph` (verified same object by refaddr) |
| ″ | 582 | `sub _seed_direct_call_arg_reprs ($graphs)`, 91 lines (582–672). **TWO** first-caller-wins guards: `:~626` declared-signature path, `:~666` shift/`$_[0]` path | **(ii)** — the plan names ONE. Two-phase gather-then-stamp restructure. **Largest single sub; the only one needing structural rework** |
| ″ | 247 | `while (_seed_direct_call_arg_reprs(\%graphs) > 0) { _seed_and_propagate_reprs(...); _resolve_direct_calls(...); }` | keep — still needed for callee-of-a-callee chains. **The fixpoint does not rescue polymorphism**: the guards make it converge on the first caller's answer |
| ″ | 1315 | `sub _element_repr ($container)`, 29 lines. Reads ONLY `$container->inputs` | **(iii)** — extend the gather set to initializers + stores |
| ″ | 1170 | `_element_repr` call site — Subscript over literal aggregate | the path the measurement analyzed |
| ″ | 1510 | `_element_repr` call site — field default, feeds `%field_elem_type` | **[VERIFIER ADDITION]** different lifetime assumptions (a field default is evaluated per-construction). Unexamined by the measurement. Overlaps 4a's B3 |
| ″ | 1214 | `@in = @in[1..$#in] if $op eq 'TernaryExpr' && @in > 1;` | **[VERIFIER ADDITION]** the condition-drop keeping `ternary-joins-arms-only.t` subtest 1 green. Preserve |
| `lib/Chalk/IR/Node.pm` | 301 | `method representation() { return $stamp }` | **[VERIFIER ADDITION] STAMP AND REPRESENTATION ARE THE SAME FIELD.** `:284-299` documents the alias as DESTRUCTIVE one-way (`set_representation('Slot')` destroys the Int TYPE) and says *"THIS IS CURRENTLY HARMLESS ONLY BECAUSE NOTHING IN lib/ READS ->stamp… a load-bearing precondition, not an accident."* All four analyses write via `set_representation` |
| `lib/Chalk/Bootstrap/Optimizer/DefinedOrFold.pm` | 94, 104–135 | calls `Analysis::_static_miss`; `_element_at` hand-duplicates `_resolve_aggregate` with a comment that the two MUST mirror | **B5** |
| `lib/Chalk/Target/LLVM/Context.pm` | 2543 | `if ($rhs_repr =~ /\A(?:Int\|ArrayRef\|HashRef\|CodeRef\|Object)\z/)` — the guard | **[VERIFIER CORRECTION]** measurement said :2541, which is `my $rhs_repr = ...`. Do NOT relax **:2543** until the join demonstrably reports the widened element type |
| ″ | 2547 | `die "GAP: Assign(Array-lvalue) rhs repr=$rhs_repr cannot be stored in an i64 Slot payload…"` | the direct consumer of (iii) and its exit criterion. **VERIFIED FIRING**: `my @arr=(1,2); $arr[0]="hello"; print $arr[0];` GAPs while perl prints `hello`. Its comment at :2534 cites `Serialize/JSON.pm` — STALE path |

### Blast radius (numbers)

- **`Analysis->run` consumers in `lib/`: 1** (`Serialize/JSON.pm:707`). **Zero test files call `run()` directly** — but **[VERIFIER ADDITION]** three test files call the *internals* white-box with a hand-built `{name => $graph}` hash: `ternary-joins-arms-only.t:39`, `typelibrary-is-the-coercion-authority.t:67` and `:99`. **A gather-then-stamp restructure of (ii) breaks them without any `run()`-level change.**
- **Subject-code line counts** (by `sed`): `_attach_call_targets` 59, `_resolve_direct_calls` 25, `_seed_direct_call_arg_reprs` 91, `_join_repr` 24, `_element_repr` 29 = **228 lines**, plus Undef drop 13, dead `'same'` 9, backend GAP guard ~15. **~260 lines touched** at full original scope; **less after re-scoping** (the fold and the guard hoist move out).
- **Test files:** `join-drops-unknown.t` (4a), `ternary-joins-arms-only.t`, `ir/son-aggregate-repr.t` (the direct (iii) surface — **4/4 passing at HEAD**, and **[VERIFIER ADDITION]** omitted from the measurement's list despite caller 2 changing), `ir/loader-reproduces-the-wire.t` (reads 16), `ir/is-narrowed-guards.t`, `ir/llvm-aggregate-latent-fixes.t` (**[VERIFIER ADDITION]** has a TODO at `:539` explicitly about element repr being *"derived from literal initializers only"* — the very path (iii) changes), **`ir/stamp-alias-preconditions.t`** (see below), `ir/typelibrary-is-the-coercion-authority.t`, `mop-fence-audit.t`, `corpus/son-corpus-wide.t`.
- **`grep -rln 'element_repr|_seed_and_propagate_reprs|Chalk::IR::Analysis' t/` returns 11 files; the measurement listed 6.**
- **`t/bootstrap/ir/stamp-alias-preconditions.t:42-125` is an ACTIVE ENFORCEMENT SWEEP** over every `.pm` under `lib/`, failing the moment any new unguarded `->stamp` reader appears (exemptions: `Node.pm`, `Analysis.pm`, and lines with `is_lattice_type` within a 4-line window). **[VERIFIER ADDITION]** — the measurement listed it with no description. **It constrains where 4b's code may live.**

### TDD build steps (re-scoped)

**Prerequisite:** 4a steps 1–3 landed; 4d landed. Both are ordering guarantees, not 4b work.

**Step 1 — (iii) container monomorphism.** Do this FIRST. *Edge traversal:* start at the `ArrayRef`/`HashRef` node N; follow `N->consumers` to Subscript nodes; for each lvalue Subscript follow `->consumers` to its Assign; gather `S = {initializer reprs} ∪ {each Assign's inputs[-1] repr}`; join `S` with `_join_repr`.

- *Failing test first:* NEW `t/bootstrap/ir/element-repr-joins-stores.t`. Load `my @arr=(1,2); $arr[0]="hello"; print $arr[0];`, assert the post-store Subscript's stamp is `'Str'` (or `'Scalar'` post-absorb), NOT `'Int'`. **RED at HEAD** — measured stamped `Int` with a `Coerce(Int->Str)` in front.
- *Second failing test (B5):* `my @arr=(1,2); $arr[0]=99; my $v=$arr[0]//5;` — assert `lli == perl == 99`. RED at HEAD (folds to the initializer).
- *Green:* in `_element_repr`, after building `@reprs` from initializers, walk consumers as above. **Plus the B5 fix**: make `_element_at` refuse to fold for any container with a store-consumer, or teach both copies together.
- *Verify:* both new tests, plus `ir/son-aggregate-repr.t` and `ir/llvm-aggregate-latent-fixes.t`. Re-run the `$arr[0]="hello"` lowering by hand: the GAP at `Context.pm:2547` must no longer fire and lli output must equal perl's `hello`. **Check the `:1510` field-default path** — it is a second caller with different lifetime assumptions. **Run `ir/stamp-alias-preconditions.t`** if any new file reads the type axis.

**Step 2 — (i) read the edge.** *Edge traversal:* Call node N with `dispatch_kind='direct'`; `N->target->graph` already exists and is the same object the hash lookup returns.

- *Failing test first:* NEW `t/bootstrap/ir/resolve-direct-calls-reads-the-edge.t` — assert `_resolve_direct_calls` produces correct stamps for a program whose graph-name hash has been perturbed (e.g. the callee bound under a different key), which only the edge can survive. **RED at HEAD** — `:545` uses `$graphs->{$node->name}`. *(The measurement's proposed red — "a classes-free wire has no targets" — is GREEN on arrival after 4d step 1.)*
- *Green:* `:545` → `$node->target->graph`.
- *Verify:* the new test, plus `ir/loader-reproduces-the-wire.t` (**must stay at 16, not rise**). **Confirm by refaddr IN THE TEST** that `$node->target->graph IS $graphs->{$node->name}` before removing the hash, so the substitution is provably identity-preserving.

**Step 3 — (ii) join over all callsites.** *Edge traversal:* **no backward edge needed.** Sweep every graph once, bucketing direct Calls by `refaddr($node->target)`. For each bucket gather `S_i = {reprs of argument i across every Call}`; join; stamp the callee's Parameter i / shift-read ONCE. **[C1]** the sweep's *output* is per-callee; if the sweep itself needs the whole program, it lives in the Loader stage, not in a transform.

- *Failing test first:* NEW `t/bootstrap/ir/arg-seeding-joins-callsites.t` pinning the measured miscompile: `sub g { my $x = shift; return $x } my $a = g(1); my $b = g("hello");` — assert the callee's shift-read stamp is the JOIN (`Str`, since `Int <: Str`), and — the discriminating assertion — that `Call#2` is NOT stamped from the other callsite's argument alone. **RED at HEAD**: the wire sends BOTH Calls as `stamp=Unknown`, and Chalk stamps BOTH `Call#2` and `Call#3` as `Str` — so `g(1)`, called with an Int, carries a Str result stamp. **The in-code defence *"lli rejects loudly rather than miscompiling silently"* is FALSE**: this is a silent wrong narrowing, spec §1's "guess" row, the only unacceptable one.
- **Bilateral coverage (mandatory per CLAUDE.md, and the verifier proved it necessary):** test **both** `Int`-then-`Str` **and** `Str`-then-`Int` call order. **[VERIFIER FINDING]** with the order reversed, both Calls stamp `Int` — **a Str value carrying an Int stamp, the more dangerous direction, which the measurement did not test despite itself citing the bilateral rule.**
- *Green:* restructure `:582-672` into two phases. Phase 1 accumulates `%by_callee{refaddr(target)}{arg_index} = [reprs]`. Phase 2 joins and stamps once. Both guards (`:~626`, `:~666`) become "stamp only if the joined value differs from what is there", preserving fixpoint termination. Keep `:247-250`.
- *Verify:* the new test plus `ir/is-narrowed-guards.t`. **Also run the three white-box internal callers** (`ternary-joins-arms-only.t:39`, `typelibrary-is-the-coercion-authority.t:67,:99`) — they call the pass functions directly and break on signature changes.
- **CAUTION ON VALUE:** the measurement states *"only 4 callees-with-multiple-callsites across all 218 corpus cases and ZERO polymorphic ones, so the 218 gate CANNOT validate this change."* **UNVERIFIED — no command, no script, no listing.** This is the most load-bearing risk claim in the sub-slice — it is the justification for shipping (ii) on one new test alone. **Measure it before relying on it.**

**Step 4 — (iv) no-tie assertion.** Cheapest; last.

- *Failing test first:* NEW `t/bootstrap/no-tie-in-the-subset.t` running the operator-form greps (`\b(tie|untie|tied)\s*\(` and `\b(tie|untie|tied)\s+[$%@]`) over `lib/`, asserting zero matches. **GREEN on arrival** — correct for a subset assertion; its job is to go RED the day someone adds a tie.
- *Green:* **NONE. No IR pass.** Ladder rung 1: the analysis does not need to exist. Chalk's subset contains no tie construct, so there is nothing in a graph to analyse; the obligation is a guard on the SOURCE SUBSET, which a grep discharges. `docs/plans/2026-08-24-access-provenance-and-the-mop.md:174-181` states the real risk in its own words: *"What must NOT happen is shipping the narrow path with no guard and no check that the subset assumption holds."*
- *Verify:* **PROVE THE RED** — point it at a fixture containing `tie my @a, 'Foo';` and confirm it fails. Otherwise the test is vacuous (fixed-vs-guarded rule).

### What is UNVERIFIED in 4b

- **"Only 4 callees-with-multiple-callsites, ZERO polymorphic"** — no evidence of any kind. Load-bearing for step 3's validation strategy.
- The 218-case / 1833-node / 210-wire-Unknown census. The verifier's independent run over 184 generated wires gave `typed=1519, Unknown=0, absent=11` and a similar-but-different wire distribution (its `Call=52` vs the verifier's `Subscript=43` as the leading op). **Same shape, different leading term; neither is reproducible from what was recorded.**
- The MOP back-edge probe: the conclusion (no back-edge; forward-sweep suffices) is sound and the shared-singleton property was independently confirmed, but the described method (*"grep on the graph object"*) is not an operation that could have produced the stated result.
- Whether `_resolve_aggregate`/`_unwrap_ref` genuinely stay in sync between `Analysis.pm` and `DefinedOrFold.pm` after (iii) — B5 supersedes the question.

---

## 4e — Pi-style flow refinement

**Verdict: NEEDS_REWORK. BLOCKED on a lattice gap the spec does not mention. Build steps 1, 2, 4, 5 survive; step 3 must be rewritten or dropped; step 6 retargets.**

### BLOCKING — B6: `defined` has no expressible piStamp, and the fix reparents the lattice under 4a

**The gap.** `TypeLibrary.pm:17-56` `%PARENT` places `Undef => 'Scalar'` as a **sibling** of `Str`, `DualVar`, `Ref`. `defined $x` proves NOT-Undef. `Scalar \ Undef` is not a lattice member, and **there is no subtract/complement operator anywhere in the file** (`grep -n "sub subtract|complement|sub without|NotUndef|Defined =>"` → rc=1, zero matches).

**[VERIFIER CONFIRMED BY EXECUTION]** `meet(Scalar, Scalar) = Scalar` — **zero narrowing.** So spec §5's own headline example, `if (defined $x)`, **has no expressible piStamp today**. A Pi built as specified is a correctly-plumbed no-op. Neither spec §5 nor plan §4e mentions this.

**The cross-slice half (C3).** Fixing it via option (a) — adding a `Defined` member under Scalar with `Str`/`Num`/`Int`/`Boolean`/`DualVar`/`Ref` reparented under it — **changes `join_types` for every existing pair.** 4a's pins (`Boolean,Int -> Str` depends on `Boolean => 'Str'` and `Int => 'Num' => 'Str'`) are verified in slice-position 3 and silently falsified in position 5.

**Fix:** make the piStamp-representation decision **NOW**, before 4a lands its pins. **Strongly prefer the non-reparenting option**: piStamp as a small separate refinement vocabulary with its own meet against lattice types, leaving `%PARENT` untouched. If reparenting is chosen instead, 4a's contract tests must be written against the FINAL lattice, and spec §5's example must be corrected.

### Blockers — true today?

| Requirement | True today | Evidence |
|---|---|---|
| The frontend can see a guard as syntax | **FALSE for B::SoN** | `perl -MO=SoN` walks the OPTREE (`~/dev/perl5-son/lib/SoN/FromOptree.pm`, 4897 lines), dispatching on op NAMES and `OPf_WANT` flags, never source text. **Spec §5 assigns CREATE to the phase that does not see syntax.** What it DOES have is better: `_handle_cond_expr` (`:4314`), 7 `make_cfg('If')` sites (`:289,:385,:430,:3825,:3931,:4428,:4665`), and at `:287-296` it already CONSTRUCTS `Defined`/`Not` nodes itself |
| The frontend can identify WHICH value the guard refines and rebind it | **true** | `FromOptree/StackSim.pm`: `field %scope` (`:11`), `define($targ,$node)` (`:75`), `lookup($targ)` (`:79`), `scope_bindings()` (`:83`), `snapshot()` (`:90` — copies every binding into the arm's sim), `merge()` (`:159`). **No new machinery required** |
| `piStamp ⊓ input.stamp` — the meet primitive exists | **true, with a caveat** | `TypeLibrary.pm:329` `meet_types` is a proper GLB. **[VERIFIER CORRECTION] it is NOT EXPORTED** — no `@EXPORT`/`@EXPORT_OK`; `use ... qw(meet_types)` FAILS at compile time. Use the fully-qualified name or add an export. The measurement asserted "no edit" without trying to call it |
| A piStamp for `defined` is EXPRESSIBLE | **FALSE** | **B6** |
| A scheduler stage exists where "delete every Pi" can run | **true** | `Scheduler/EagerPinning.pm:57-79` builds `@body` ONLY by walking `$exit->control_in` backward; `_expand_node` (`:151-160`) special-cases only If/Loop/TryCatch. **Pure value nodes never enter the schedule** — so the delete is a separate use-def rewrite after `schedule()` returns |
| T1 exists as a Graph→Graph transform | **FALSE** | prerequisite chain 4c→4d→4a→4b |

**On soundness (OPEN DISAGREEMENT, partially resolved).** Spec §5 claims *"soundness falls out of dominance with no scheduler changes."* **COULD NOT CONFIRM as stated.** The scheduler never positions value nodes, so "a Pi cannot float above its guard" is not a property the scheduler enforces. Positioning happens in the BACKEND: `Target/LLVM/Context.pm` is a demand-driven recursive emitter with a per-node-id SSA cache (`:1253`, bypassed only for mutable reads at `:1225-1240`). A Pi's guard input would NOT prevent that cache from serving a ref emitted inside a guard to a consumer outside it. **Therefore §5's "Scheduler DELETES every Pi" is load-bearing, not tidiness** — soundness rests on the DELETE step, not on dominance. Chalk has shipped this exact bug class before (MEMORY.md `[[cross_graph_id_keyed_cache_collisions]]`: id-keyed caches are "SYSTEMIC").

### Verified edit surface

| File | Line | What is there now | What must change |
|---|---|---|---|
| `lib/Chalk/IR/Node/Pi.pm` | — | **DOES NOT EXIST.** `grep -rn '\bPi\b' lib/ t/` → matches only in `docs/specs/` | NEW FILE. Must subclass `Chalk::IR::Value` (not `Node`) — `Value.pm` states the predicate is `$node isa Chalk::IR::Value` and is CLOSED. Needs `field $pi_stamp :param :reader`, `method operation() { 'Pi' }`, `sub identity_kind`, `method content_hash`, `method staleness_kind` |
| `lib/Chalk/IR/NodeFactory.pm` | 91 | `my %DATA_CLASSES = map {...} qw(` — ~75 op names | add `Pi` + a `use` line among the ~90 at `:9-88` |
| ″ | 291–292, 294 | `my $class = $DATA_CLASSES{$op} // $CFG_CLASSES{$op} or die "Unknown data node operation";` then `if ($class->identity_kind eq 'per_call')` | **[VERIFIER CORRECTION]** measurement cited :313, which is inside `make_unique`'s body. **No edit** if Pi declares `identity_kind` — the factory asks the TYPE |
| ″ | 327, 338 | `make_unique` looks up `%DATA_CLASSES` ONLY; `make_cfg` looks up `%CFG_CLASSES` ONLY | **[VERIFIER ADDITION]** three distinct lookup paths with different fallbacks; the measurement models one. Die sites: 292, 327, 338 (+311, 404 for CFG) |
| `lib/Chalk/IR/Serialize/JSON.pm` | 78 | `sub _extract_fields ($node, $id_remap)` — `if/elsif` chain; falls through returning undef for unknown ops | add a `Pi` arm emitting `pi_stamp` + the guard's remapped id. **Without it a Pi silently serializes with no piStamp — no error** |
| ″ | 495 | `sub _deserialize_graph ($method_data)`, elsif chain `:498-600` | add a `Pi` arm restoring `pi_stamp` and resolving the guard index |
| ″ | 477–479 | `my $phi_backedge_slot = ($op eq 'Phi' && @input_idx == 2 && $input_idx[1] >= @nodes) ? 1 : -1;` | **[VERIFIER ADDITION]** the forward-reference validator is **HARDCODED to Phi**, not a general mechanism a Pi can opt into. If a Pi's guard Proj ever needs deferred patching this is a real code change, not an ordering note |
| ″ | 20 | `%CFG_OPS = qw(Start Return Unwind If Proj Region Loop)` | **NO edit** — Pi is a VALUE node. Recorded because it is the table a builder would wrongly reach for |
| `lib/Chalk/IR/Graph/TypedInvariant.pm` | 157–158, 410–412 | `my $input_repr = $input->representation();` then `return unless defined $input_repr;  # undef = not yet assigned; skip` | **NO EDIT NEEDED — [VERIFIER REFUTATION, see below]** |
| `lib/Chalk/IR/Node.pm` | 301 | `method representation() { return $stamp }` — on the BASE class | **[VERIFIER CORRECTION]** every node including every control node answers it, returning undef |
| ″ | 150 | `method staleness_kind() { return 'mutable_read' }` — the default | **[VERIFIER CORRECTION]** measurement said `~140`; those are comments |
| `lib/Chalk/IR/Graph.pm` | 133 | `method nodes()` — pass 2 topo-sorts using "ONLY producer edges (inputs, plus a Phi's region)". `:159-175` names the loop-Phi backedge as *"the sole, sanctioned forward reference"* | verify a Pi's Proj guard participates correctly. The docstring calls this *"the cross-repo walk-order contract; the corpus gate enforces it"*; MEMORY.md warns **"DON'T change Graph::nodes() walk order"** |
| `lib/Chalk/IR/Analysis.pm` | 87–124 | `%_COMPUTED_REPR`; `Phi/TernaryExpr/DefinedOr => 'join'` at `:93`; `Defined Not` forced Boolean at `:119-124` | STRENGTHEN owner. A Pi's effective stamp is `meet_types(pi_stamp, input.stamp)`, RECOMPUTED — **not a join, not a fixed stamp.** Needs its own rule |
| ″ | 298 | `# _assert_value_nodes_are_typed(\%graphs);` | **[VERIFIER CORRECTION] ALREADY COMMENTED OUT.** The blocker implied action; spec §9 AC #4's premise is already satisfied |
| `lib/Chalk/Scheduler/…/EagerPinning.pm` | 151 | `method _expand_node($node)` — If/Loop/TryCatch, else a `stmt` Item. `@body` built `:57-79` from `control_in` only | DELETE owner. **Cannot be an `_expand_node` arm** — pure value nodes never enter `@body`. A separate use-def rewrite after `schedule()` |
| `lib/Chalk/Target/LLVM/Context.pm` | 1275+ | value-lowering elsif chain: `'Coerce'` :1275, `'Phi'` :1315, `'Proj'` :1324… 122 `op eq` sites in 8149 lines | **NOTHING, deliberately.** Spec §5: *"A Pi reaching the backend is a bug."* **[VERIFIER PERFORMED THE CHECK THE MEASUREMENT DEFERRED]** the tail IS loud: `else { die "LLVM backend: cannot lower op=$op (not in literal-arithmetic slice)" }` |
| ″ | 1253 | `if (exists $self->{cache}{$id} && !$self->_reads_mutable_location($node)) { return ... }` | **NOTHING if the scheduler deletes every Pi.** Documents WHY the delete is load-bearing |
| `lib/Chalk/Grammar/Perl/TypeLibrary.pm` | 329 | `sub meet_types($left,$right)` — a correct GLB | **NOT EXPORTED** (see blockers). Also: it can return `None`, which spec §4's exit condition never discusses. **Spec gap** |
| ″ | 17 | `%PARENT` — `Undef => 'Scalar'` sibling of `Str`/`DualVar`/`Ref` | **B6** |
| `~/dev/perl5-son/lib/SoN/IR/NodeFactory.pm` | 93 | `my %DATA_CLASSES = map {...} qw(` — the producer's mirror | add `Pi` + `lib/SoN/IR/Node/Pi.pm`. Die sites: **:365 and :393** say `"Unknown data node operation"`; **[VERIFIER CORRECTION] :355 says `"Unknown node operation"` (no "data")**, and :311/:404 are the CFG variants the measurement omits |
| `~/dev/perl5-son/lib/SoN/FromOptree.pm` | 289 | `make('Defined')` → `make('Not')` → `make_cfg('If')` → `make_cfg('Proj', index=>1)` — the producer ALREADY builds all four for `E // return X` | CREATE owner. **Cheapest proof-of-concept** — the Proj and the guarded value are both already in hand |
| `~/dev/perl5-son/lib/SoN/FromOptree/StackSim.pm` | 75 | `method define ($targ, $node)` | the exact rebinding mechanism a Pi needs: at the If, `$arm_sim->define($targ, $pi)` |
| `lib/Chalk/Bootstrap/Perl/Actions.pm` | — | 3405 lines, 7 `make('If')` sites (`:2530,:2593,:2720,:2859,:2969,:3120,:3304`) | **[VERIFIER ADDITION] Chalk's OWN frontend — the only phase that DOES see syntax, and therefore the natural CREATE owner for a single-repo first version.** The measurement cited it only to refute spec §5, never in the edit surface |

### Blast radius (numbers)

- **Node-class parity: 88 = 88.** `lib/Chalk/IR/Node/` has 88 `.pm` files; `~/dev/perl5-son/lib/SoN/IR/Node/` has 88. **Adding a type to one repo breaks the mirror.** `lib/SoN/IR/Value.pm` states the wire carries only `op` and both sides map it to a class independently, so an unknown `op` hits a `die` at load. **CONSUMER-FIRST is the only safe order.**
- **New-node-type proxies:** `Coerce` (most recently added) — **95 mentions across 8 `lib/` files, 40 `t/` files** (verified exactly). `Proj` (a control node with an index field) — **30 `'Proj'` string-compares across 8 `lib/` files** — **[VERIFIER CORRECTION]**, measurement said 20 files, a 2.5× inflation of the proxy the size estimate is calibrated on.
- **A Pi is harder than either:** `Coerce` is value-in/value-out; `Proj` is control-only. **A Pi is the first node in the IR taking a CONTROL node as a producer edge of a VALUE node.**
- **Estimated lines: ~700** — split ~150 (Pi.pm + factory + serialize, both repos) / ~120 (T1 strengthen) / ~60 (scheduler delete) / ~40 (TypedInvariant) / ~200 (FromOptree) / ~150 (tests). **UNVERIFIED — this is an estimate, not a measurement**, and it is partly calibrated on the refuted Proj proxy. The ~40 for TypedInvariant is now known to be **zero** (see step 3). The instruction was "MEASURE it"; this figure does not comply.
- **Test files:** `ir/node-identity-kind.t` (`_ops()` at **:128**, glob at **:131**, `%REQUIRED` at **:142/:144** — **[VERIFIER CORRECTION]**, measurement said :126/:141; substance correct: the glob auto-enrols every class, and a Pi with a required `:param` the test's 4 `_build` shapes at `:160-175` cannot satisfy lands in `@unbuildable` and is **SILENTLY not checked**. Verified green on HEAD, 5 subtests), `ir/loader-reproduces-the-wire.t` (16, must reach 0 per spec §9 AC#1), `ir/emitted-ir-is-well-typed.t`, `ir/graph-nodes-iterative.t`, `ir/graph-bidirectional-traversal.t`, `ir/llvm-stale-value-cache.t`, `ir/llvm-reassign-soundness.t`, `corpus/son-corpus-wide.t`, `corpus/shape-subset-check.t`, `corpus/mdtest.t`.
- **[VERIFIER ADDITION] `t/lib/` is missing from the test list entirely** — `t/lib/Chalk/CodeGen/Harness/MdtestCorpus.pm` and `.../ReturnNodePerlDriver.pm` both reference `Coerce`/`'Proj'`. This is exactly the "consumer count that missed `t/` or `t/lib/`" failure mode.

### TDD build steps

**Step 1 — RESOLVE THE LATTICE GAP FIRST.** Do not write a Pi node until `defined` has a piStamp value. **This step's DECISION half must happen before 4a (C3/G0).**

- *Failing test first:* NEW `t/bootstrap/ir/pi-stamp-vocabulary.t` — assert that the type proved by `defined $x` on a `Scalar`-stamped input is expressible and is **strictly narrower than `Scalar`**. **CANNOT PASS on HEAD**: no complement operator (rc=1) and `Undef` is a sibling under `Scalar`.
- *Green:* **preferred** — define the piStamp vocabulary as a separate small enum with its own meet against lattice types, leaving `%PARENT` untouched (C3). **Alternative (only with explicit coordinator sign-off)** — add `subtract_type($from,$remove)` handling the Scalar/Undef case, or add a `Defined` member with reparenting. **This decision is the real content of step 1 and it is a SPEC GAP, not an implementation detail.**
- *Verify:* the new test, **plus** `ir/emitted-ir-is-well-typed.t` and the join/meet unit tests — **and, if reparenting is chosen, 4a's landed join pins**, which change meaning.

**Step 2 — the node type, Chalk side only** (consumer-first is the only safe cross-repo order).

- *Failing test first:* NEW `t/bootstrap/ir/pi-node.t` — build a Pi via the factory; assert `operation eq 'Pi'`; assert **two Pis over the same input at different guards are DISTINCT nodes**; assert `effective_stamp == meet_types(pi_stamp, input.stamp)`. RED: `die "Unknown data node operation: Pi"` at `NodeFactory.pm:292`.
- *Green:* `lib/Chalk/IR/Node/Pi.pm` — `class Chalk::IR::Node::Pi :isa(Chalk::IR::Value)`, `field $pi_stamp :param :reader`, `method operation() { 'Pi' }`, **`sub identity_kind { 'per_call' }`** (a refinement is position-dependent; hash-consing two Pis with the same piStamp+input merges refinements from DIFFERENT guards — the exact C2 bug spec §5 row 3 names), `method staleness_kind() { 'transparent' }`, `content_hash` including `pi_stamp` + guard id. Register in `%DATA_CLASSES` + `use`. **Call `meet_types` fully-qualified or add the export** — it is not exported.
- *Verify:* `pi-node.t` **and** `ir/node-identity-kind.t` — the latter auto-enrols Pi via its glob at `:131` and reports it in `@unbuildable` unless a `%REQUIRED` entry is added at `:144`. **Confirm Pi appears in `@checked`, not `@unbuildable`.**

**Step 3 — REWRITE OR DROP.** **[VERIFIER REFUTATION BY EXECUTION]**

The measurement called this "the genuinely novel structural change" and built its entire red test on: *"TypedInvariant calls `$input->representation()` unconditionally on a Proj, which is a control node with no such method/value."*

**This is false.** `representation()` is defined on the BASE class `Chalk::IR::Node` at `:301` as a deprecated alias for `stamp`, not on `Value`. The verifier built a real Proj via the factory and called it: **it did not die; it returned undef.** Both cited sites already guard undef on the **immediately following line** — `:158` is `return unless defined $input_repr;  # undef = not yet assigned; skip`, and `:411-412` is the same shape with `next`. **A Pi's Proj operand is SKIPPED by existing code with no exemption, no edit, and no violation.**

The proposed red test **would PASS on HEAD** — a vacuous green, the failure mode MEMORY.md `[[feedback_acs_must_discriminate]]` records.

**What to do instead:** if a real control-input-on-a-value-node problem exists, it is in `Graph::nodes()` topo ordering (**untested by either agent**, and MEMORY.md warns against changing that walk) or in `content_hash`. Write the red test against **that**, or drop the step. Do not carry the TypedInvariant story forward.

- *Failing test first (replacement):* NEW `t/bootstrap/ir/pi-guard-in-topo-order.t` — build `Pi(value, guard=Proj)` inside a graph, call `Graph::nodes()`, assert the Proj precedes the Pi and no existing node's relative order changes vs. the same graph without the Pi. **RED status UNKNOWN — establish it before writing the green.**
- *Verify:* `ir/graph-nodes-iterative.t`, `ir/graph-bidirectional-traversal.t`.

**Step 4 — wire round-trip, Chalk side.**

- *Failing test first:* NEW `t/bootstrap/ir/pi-round-trip.t` — `to_json` then `from_json` a graph containing a Pi; assert it survives with `pi_stamp` and guard edge intact. RED: `_extract_fields` has no Pi arm, so `pi_stamp` is dropped silently.
- *Green:* add the emit arm at `JSON.pm:78-130` and the load arm at `:495-600`. **Check `:477-479`** — the forward-reference validator is Phi-hardcoded; a Pi's guard Proj must be emitted BEFORE the Pi, or that validator needs a real change.
- *Verify:* the new test, and `ir/loader-reproduces-the-wire.t` **must not increase from 16**.

**Step 5 — the scheduler delete.** 4e is CHEAPEST here; build it before any frontend work.

- *Failing test first:* NEW `t/bootstrap/ir/pi-deleted-by-scheduler.t` — schedule a graph containing a Pi, assert NO node reachable from the schedule is a Pi, and every former Pi consumer now reads the Pi's value input directly. RED: nothing deletes Pis.
- *Green:* after `schedule()` returns, rewrite every Pi consumer's input from the Pi to `$pi->inputs->[0]`, then drop the Pi. **A pure use-def rewrite — no schedule item is involved**, because a Pi is never IN the schedule (`:57-79` builds `@body` from `control_in` only; `_expand_node` at `:151-160` handles only If/Loop/TryCatch). **UNVERIFIED that a use-def rewrite is safe/sufficient at that pipeline point** — `Node.pm` has `remove_consumer`/`add_consumer` but no consumer-rewrite helper was identified. Establish this before building.
- *Verify:* the new test, `ir/dominators.t`, `ir/elaborate.t`. **Also `ir/llvm-stale-value-cache.t` and `ir/llvm-reassign-soundness.t`** — the adversarial value-cache proofs named at `Context.pm:1237-1240`; the delete is what keeps `:1253`'s id-keyed cache from serving a guard-local ref outside its guard.

**Step 6 — a T1-created Pi for `defined` only, in CHALK'S OWN FRONTEND.** **[RETARGETED per the verifier]** The measurement deferred creation to the cross-repo frontend; by its own argument, `lib/Chalk/Bootstrap/Perl/Actions.pm` is the only phase that sees syntax and is the natural owner for a single-repo first version.

- *Failing test first:* NEW `t/bootstrap/ir/pi-narrows-under-defined-guard.t` — a graph shaped like `if (defined $x) { ...use $x... }` where `$x` enters as the widest expressible type; assert the use **inside** the guard has the narrower effective stamp and the use **outside** does not. RED: no Pi is created.
- *Green:* create a Pi at each If whose condition is `Defined(v)` (or `Not(Defined(v))`), guard input = the corresponding Proj, rebinding consumers dominated by that Proj. Dominance is available: `lib/Chalk/IR/Schedule/Dominators.pm` (484 lines) already computes it.
- *Verify:* the new test; then the coordinator runs the 218 gate — it must hold, per spec §9 AC #5.

**Step 7 — the cross-repo frontend. LAST**, because it is the only step that breaks 88=88 parity.

- *Failing test first:* in perl5-son, a wire-emission test asserting a Pi appears in the JSON for `sub f { my $x = shift; if (defined $x) { return $x } return 0 }`. RED: `die "Unknown data node operation: Pi"` at `SoN/IR/NodeFactory.pm:365` **or `:393`** — **not `:355`**, which carries a different message.
- *Green:* mirror `Pi.pm`, register in `%DATA_CLASSES` (`:93`), add the emit arm, create Pis at the If sites (`:289` already builds Defined/Not; StackSim supplies rebinding). **SEPARATE REPO — coordinate; do not run `git zhi` there.**
- *Verify:* the cross-repo corpus gate (coordinator). **UNVERIFIED:** `SoN/Compare.pm` diffs by op name and stamp, so a Pi on one side only reports as "Extra in B" — cited at `:106`, **not verified, no output quoted**.

### What is UNVERIFIED in 4e

- **The ~700-line total and all six components.** Labelled MEASURED; none is a count, and it is partly calibrated on the refuted Proj proxy.
- Whether a use-def rewrite is safe/sufficient at the post-`schedule()` point (step 5).
- `SoN/Compare.pm:106` and its "Extra in B" behaviour.
- `lib/Chalk/Target/LLVM.pm` "mentions Coerce; same op-vocabulary surface" — **the only blast-radius entry with no evidence of any kind.** No line, no count, no grep.
- Whether `Graph::nodes()`'s topo order is actually perturbed by a control-node producer edge on a value node — **neither agent tested it**, and it is now step 3's replacement subject.

---

## Plan corrections needed

The coordinator should fix these in `docs/plans/2026-08-24-loader-analysis-pipeline.md`. Each is a place where the plan asserts something HEAD contradicts.

### Stale file:line references (§4a)

The plan cites `_join_repr` at `Serialize/JSON.pm:1352` with callers `:1623`/`:1699`, and the three improvisations at `:1365`/`:1597`/`:1580`.

**All six are past EOF in a file that no longer contains the function.** `wc -l lib/Chalk/IR/Serialize/JSON.pm` = **735**. `grep -n '_join_repr'` on that file → rc=1, ABSENT. The move landed in commit f92c6869, *"refactor(ir): move the inference passes out of the loader, bodies and all."*

Real locations, re-derived and confirmed by four independent agents:

| Plan cite | HEAD reality |
|---|---|
| `Serialize/JSON.pm:1352` (defn) | `Analysis.pm:1004` (doc comment from **:988**) |
| `:1623`, `:1699` (callers) | `Analysis.pm:1266`, `Analysis.pm:1342` |
| `:1365` (Unknown drop) | `Analysis.pm:1017-1018` (comment 1007–1016) |
| `:1597` (Undef drop) | `Analysis.pm:1240-1241` (comment 1228–1239) |
| `:1580` (`'same'` bail) | `Analysis.pm:1218-1226`, guard at `:1192` |

**The generalisation holds: no `file:line` anywhere in plan §4a–4e can be trusted without re-derivation.**

### §4a — the `'same'` rule is already dead code

The plan lists *"the `same` rule for And/Or, which bails entirely on any mismatch"* as one of three **live** improvisations. `%_COMPUTED_REPR:110` reads `And => 'join', Or => 'join'`. No op maps to `'same'`; `$rule` is assigned only at `:1191` from that table. Dead since commit 6d9fc083 (*"feat(llvm): a merge coerces its ARMS; floor 190 → 191"*), which **predates this plan**.

Deleting it is zero-behaviour-change dead-code removal. The plan's prose describes history, not HEAD, and would send a builder hunting for something that is not there.

### §4a — "no regression" is wrong for the three cases that actually change

The plan reasons that the Undef-drop deletion moves graphs *"from 'no repr' GAP to 'Scalar has no machine representation' GAP… A different GAP with a better message is still a GAP: no regression."*

The GAP-to-GAP mechanism is verified. **The conclusion is wrong for L3b/L3c/L3d** — they are not GAPping today; all three are declared **L: GREEN**. The transition is **GREEN → GAP**, a real gate regression (218 → 215). The plan's framing would be correct for a case that already GAPs; it does not describe the cases that change.

### §4a — the plan lists FOUR improvisations; every measurement analyzed three

Plan lines ~878–884 name the backend's `$repr // 'Int'` defaults, *"which guess when the loader supplied nothing."* **Four live sites** (B4). Per spec §1 a silent Int guess is the only unacceptable outcome. Add an owner to the plan.

### §4b — the corpus prose contradicts the change

`t/corpus/mdtest/logical.md:1032-1035`, L3d's numbered point 2: *"Undef contributes no value to widen, so it is dropped before the join and the defined arm's type wins."* That becomes false. Per project memory (`[[corpus_dual_contract]]`) ir-blocks are spec AND optimizer contract; the prose must be rewritten in the same commit as the stamp edits. **The plan budgets deletion in `lib/` but not the corpus-contract rewrite.**

### §4c — "three harnesses" is wrong twice over

Plan:1013: *"three harnesses — ProgramRunner, Mode2Adapter, Phase5LibCoverage — each run from_json then lower(mop => ...) inline, identically. The pipeline exists three times, in test code, with no single seam."*

**There are FIVE.** The fourth is `son-corpus-wide.t:60-119` — the corpus gate itself, asserting the 218 floor at `:322`, and named by `Mode2Adapter.pm:125` as the ORIGINAL it was cloned from. The fifth is `son-e2e.t:66` — same sub name, full sequence, 253 lines, live assertions at `:224`/`:230`.

And **they are not identical**, in four load-bearing ways, each documented in-code as deliberate:

- **Producer flags.** `ProgramRunner.pm:182` uses `$PKG_EXCLUDE` (17 `not_package=` terms, built `:50-67`); `Mode2Adapter.pm:151` uses `package=main` (INCLUSION); `Phase5LibCoverage.pm:62` uses no package filter plus an extra `-I`; `son-corpus-wide.t:70` uses `package=main` plus one per split-out class. `ProgramRunner.pm:20-49` carries a 30-line comment explaining the difference is LOAD-BEARING; `Mode2Adapter.pm:140-150` carries the mirror-image comment.
- **`program_mode`.** Passed by 2 of 5; must NOT be passed by 3. And `emitted-ir-is-well-typed.t:108` toggles it per case within one caller.
- **Entry selection.** One named graph vs many MOP-derived units.
- **Failure policy.** Abort-on-first vs accumulate-per-unit.

### §4c — "there is no pipeline" is partially false, and the difference changes the work

A pipeline DOES exist, fused inside the loader: `Serialize/JSON.pm:707` calls `Chalk::IR::Analysis->run`, and that is **Analysis's only caller repo-wide**. `:701-706` states the intent: *"from_json should not call this at all… The call stays only so the ~40 existing callers keep working during the transition."*

4c's real job is not "assemble scattered stages" — it is **"create a seam OUTSIDE `from_json` so the fused Loader+Analysis can later be split."** A different, and smaller, construction.

### §4c / spec §7 — four of the six named stages cannot be owned today

*"Build one object owning `Loader > T1 > Optimizers > T2 > Optimizers > Scheduler`."* T1 and T2 do not exist. "Optimizers" has zero invocations in any assembler. The Scheduler runs **inside** the backend (`Target/LLVM.pm:53-58` constructs `Dominators` and `Elaborate` from the return node before delegating). The object can own exactly ONE named stage (Loader) plus a backend call the spec does not list.

### §4d — the Call MOP handle already exists

Plan ~:1032 frames *"A Call resolves its callee through a MOP handle; that handle IS the inter-unit edge"* as work to be done. **It is shipped Phase-4 functionality.** Spec §6's quoted phrase is lifted verbatim from a comment on `Node/Call.pm:35`, a field live for months, with two writers and three readers that traverse it. Both pinning tests pass at HEAD (5/5, 7/7). **The framing is inverted.**

What is actually missing is that it is only built for ~15% of programs — the classes guard at `Analysis.pm:197`, which plan §4d does not mention at all.

### §4d — `_build_registry_from_mop` does NOT go away

Plan ~:1038: *"`_build_registry_from_mop` then rebuilds a second copy at lowering time and goes away with this change."* **False on both halves.** It is a lowering-specific projection computing six classes of fact the MOP does not carry, every one still needed after 4d (all six independently re-confirmed):

1. `vtable_slot => $mslot++` dispatch-slot allocation (`LLVM.pm:546`, `:594`)
2. `_flatten_inheritance` merging parent methods/fields/adjusts into each child (`:248-313`) — the MOP stores parents by reference, unflattened
3. `body_node`/`body_return` (`:516`, `:544`) enforcing an exactly-one-Return GAP (`:377-385`) that lives nowhere else
4. `return_repr` with the `_require_repr` fallback when the declared type is Unknown (`:521-529`)
5. synthesized `:reader` accessor records carrying `is_reader_synth`/`reader_field_index` (`:588-598`)
6. two policy filters — `next if $s->uses_args` (`:510`) and `next if $cls->name eq 'main'` (`:352`) — each with a multi-paragraph rationale

Replace the claim with a note that its retirement belongs to the LLVM-reads-MOP-directly line of work (`docs/plans/2026-06-11-llvm-reads-mop-directly.md`), not to 4d.

### §4d — a stale comment inside the code

`Analysis.pm:300-301`: *"$mop is returned only in list context; scalar context stays \%graphs for the existing single-return callers."* **This is false of its own function** — `run()` returns a 2-element list unconditionally. It was copy-pasted from `from_json` during the slice-1 extraction (f92c6869). Fix or delete when step 4 lands.

### §4d — the ordering sentence's own line number

§4d spans **:1030-1042**, and the ordering sentence `4c → 4d → 4a → 4b → 4e` is at **:1042**, not the `:1030-1039` several measurements cite. Small, but this plan's own thesis is that unverified line numbers are worthless.

### §5 — the arrived-absent count

Plan:1086 says *"Measured: 10 nodes across the 218-case corpus."* Two independent measurements got **11** (Phi=8, Call=2, Ref=1 in one run; Call=3, Phi=7, Ref=1 over 184 wires in another). Reported rather than silently corrected — it may be drift, or a difference in which nodes were walked.

### Spec §5 — two corrections

1. *"the only phase that sees `if (defined $x)` as syntax"* — assigned to B::SoN, which walks the optree and never sees syntax. Chalk's own `Actions.pm` is that phase.
2. *"soundness falls out of dominance with no scheduler changes"* — COULD NOT CONFIRM. The scheduler never positions value nodes; soundness rests on the DELETE, not dominance.

### Spec §5 / §9 — two gaps

1. **The lattice gap (B6):** `defined` has no expressible piStamp. The spec's own worked example cannot be given a value today.
2. **`meet_types` can return `None`**, which spec §4's exit condition (*"No Value node leaves T1 stamped Unknown"*) never discusses. A Pi whose piStamp contradicts its input yields `None`.

### Spec §9.5 vs 4a step 4

The 218 floor is an acceptance criterion; 4a step 4 as designed cannot satisfy it without T2. Either amend §9.5 or park the step (this document parks it).

### Every measurement's "MEASURED, NOT ESTIMATED" banner

Applied over figures that are estimates or wrong: 4c's ~120-line unwritten file and 51-line span total (true ~65); 4d's 25-vs-26 subs, 32-vs-33 scalar sites, 50-vs-48 mop lines, `:985`-vs-`:988`; 4b's `%_COMPUTED_REPR` tally (Str and Boolean undercounted — the correct counts are 9 join, 10 Int, 2 Num, 3 Str, 2 Boolean, and the table runs 81–**126**) and its `ternary-joins-arms-only.t` misreading; 4e's Proj proxy (8 files, not 20), its ~700-line total calibrated on it, and off-by-two anchors at `:126`/`:141`, `:313`, `:355`, `:140`, `:2541`.

None changes a verdict. Collectively they mean **a builder cannot trust any anchor without re-deriving**, which defeats the point of a measurement. **One correction pass per measurement, applying its verifier's numbers verbatim, before any document reaches a builder. Drop the banner from figures about unwritten code.**

---

## What the coordinator must gate-verify, and between which steps

"Gate" below means `t/bootstrap/corpus/son-corpus-wide.t` — the ~10-minute run the coordinator owns. Never in a subagent. Serialize: the gate reads perl5-son LIVE, and parallel agents contaminate each other's readings (MEMORY.md `[[no_producer_version_pin_serialize_execution]]`).

### G0 — BEFORE any building

**A decision gate, not a test run.**

1. **The piStamp representation decision (C3/B6).** Separate refinement vocabulary, or `%PARENT` reparenting? This must be settled before 4a step 2 lands its join pins, or slice-position 5 silently falsifies slice-position 3. Strongly prefer the non-reparenting option.
2. **Spec §9.5 vs 4a step 4 (B2).** Confirm step 4 is PARKED, or amend §9.5. Without this, 4a cannot complete inside slice 4.
3. **An owner for `$repr // 'Int'` (B4).** Four sites at `Context.pm:3349`, `:4071`, `:5801`, `:6827`. In slice 4, or filed with a target?
4. **The 4c transforms contract (B1/C1).** Confirm `$g -> $g` per graph.
5. **4b re-scoped (C2).** Confirm the fold and the guard hoist are struck from 4b.

Record all five. They are decisions the measurements could not make.

### G1 — after 4c step 6 (all five assemblers migrated)

**Gate run. Floor: `gate_green >= 218`.**

This is the first gate-affecting change in the slice — step 6 edits the gate file itself. Also confirm at this point that **all five** assemblers route through the Pipeline. **If any is left inline, STOP**: 4d step 4 and 4a step 4 both re-create the 2026-08-25 mechanism (C5), and spec §7's acceptance logic does not follow.

### G2 — after 4d step 1 (classes guard dissolved)

**Gate run. Floor: 218.**

The measurement called this the riskiest step. The verifier's scratch experiment predicts **byte-identical stamps on all 218 and byte-identical LLVM IR**. If the gate moves at all, the experiment's premise is wrong and the step must be reverted, not patched.

Also run `t/bootstrap/mop/*.t` and the three `(undef, $mop)` sites (`mop/sub-replay.t:28`, `ir/son-classes-replay.t:60`, `loader-return-type.t:32`).

### G3 — after 4d step 3 (method dispatch onto the edge)

**Gate run. Floor: 218.**

Second high-risk step: it changes how every method call gets typed. **Before landing, resolve the OPEN DISAGREEMENT on revert-independence** — in scratch, land 1+2+3, revert 3 alone, confirm the gate returns to its post-G2 value. The measurement asserts independence; the verifier notes step 3 touches the `:238` fixpoint that step 1 newly feeds.

### G4 — after 4d step 4 (return-shape collapse)

**Gate run. Floor: 218.**

The 27-site edit, closest in shape to the change that took the gate 218 → 136. Plus the 25 affected files individually. **Hand-re-read all three one-value-LIST silent-survivor sites** — `ir-serialize-json.t:238`, `ir/lowerable-stamp-admission.t:47`, `ir/loader-reproduces-the-wire.t:123`. They keep working through this change and cannot be relied on to fail.

### G5 — BEFORE 4a step 2, a measurement gate (no gate run)

**B3 must be discharged first.** Re-run the total-join simulation instrumenting:

- BOTH `_element_repr` callers (`Analysis.pm:1170` and `:1510`), including the `%field_elem_type` → field-Subscript path at `:1541-1548`
- nodes frozen-by-first-Scalar across fixpoint iterations, given `_is_narrowed('Scalar') == true` at `:448-450` and the guard at `:1148`
- whether a Scalar-joined method return can reach the `die` at `:1598-1605`

Decide: withhold the join result until the fixpoint stabilizes, or teach `_is_narrowed` that Scalar is refinable. **The "exactly 3 movers" figure is not usable as a revert criterion until this is redone.**

### G6 — after 4a steps 1–3

**Gate run. Floor: 218 — and the count must NOT move.**

All three steps are measured corpus-inert. Any movement means the inertness claim is wrong.

Also: after step 1, re-run the 240-case probe confirming drop-vs-absorb disagreement is still 0. After step 2, re-run the simulation confirming ZERO stamp changes (the Undef drop at `:1240` still runs ahead). **Verify `ternary-joins-arms-only.t` explicitly** — preserving the TernaryExpr condition-drop at `:1214` is what keeps subtest 1 green. Commit step 3 separately.

### G7 — BEFORE 4b step 3, a measurement gate (no gate run)

**Measure the claim "only 4 callees-with-multiple-callsites, ZERO polymorphic."** It is UNVERIFIED and it is the entire justification for shipping (ii) on one new test alone. If polymorphic callees exist in the corpus, the gate DOES validate the change and the risk profile inverts.

### G8 — after 4b steps 1–3

**Gate run. Floor: 218.**

Step 1 (iii) changes container typing and the `Context.pm:2547` GAP; step 3 (ii) changes how every multi-callsite callee's parameters are stamped. Also run the three white-box internal callers (`ternary-joins-arms-only.t:39`, `typelibrary-is-the-coercion-authority.t:67`, `:99`) and `ir/stamp-alias-preconditions.t` if any new file reads the type axis.

**B5 acceptance:** the store-then-defined-or case must prove `lli == perl == 99`.

### G9 — after 4e step 1 (lattice decision implemented)

**Gate run if `%PARENT` was reparented; skip if the separate-vocabulary option was taken.**

If reparented, **4a's landed join pins must be re-verified against the new lattice** — this is C3 arriving. Run `ir/emitted-ir-is-well-typed.t` and the join/meet unit tests either way.

### G10 — after 4e step 6 (T1-created Pi in Chalk's frontend)

**Gate run. Floor: 218**, per spec §9 AC #5.

### G11 — after 4e step 7 (cross-repo)

**Cross-repo corpus gate.** This is the step that breaks 88=88 node-class parity. Consumer-first ordering means Chalk must already know `Pi` before perl5-son emits one; a producer emitting `Pi` before the consumer knows it **dies at load**.

### Standing verification obligations, at every gate

- **`ir/loader-reproduces-the-wire.t` must never rise above 16** (spec §9 AC#1 target: 0). Check it at G1, G2, G4, G6, G8.
- **Prove every RED before writing its green.** Two named red tests in this plan are demonstrably vacuous (4a step 4's `logical.t`, 4e step 3's TypedInvariant story) and one more is green-on-arrival after re-scoping. `git-zhi-verify` extracts ONLY `- [ ]` checkbox bullets; write single-line ACs and run them by hand.
- **Never `--no-verify`.** Never a subagent for the gate.