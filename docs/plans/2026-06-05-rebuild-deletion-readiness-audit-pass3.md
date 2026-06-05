# Block Control-Chain Rebuild — Deletion-Readiness Audit (PASS 3)

**Date:** 2026-06-05
**Branch:** phase1-lateral-bindings @ f2af91d2 (clean tree)
**Auditor role:** read-only. No `lib/` or `t/` modifications. Probes ran in `/tmp` and were deleted.
**Subject:** can the Block control-chain rebuild (`lib/Chalk/Bootstrap/Perl/Actions.pm` 1644-1727,
toggled by `disable_control_rebuild`/`enable_control_rebuild`, default ENABLED) now be safely DELETED?
**Predecessors:**
- `docs/plans/2026-06-04-rebuild-deletion-readiness-audit.md` (RED — postfix-modifier blocker)
- `docs/plans/2026-06-04-rebuild-deletion-readiness-audit-rerun.md` (RED — C-style `for` hoisted-init blocker)

Both prior blockers are FIXED (commits 6cdcb15b, e5b71467) and re-confirmed below.

## VERDICT: RED — a THIRD blocker exists (plus a fourth, related divergence).

The same class of bug that the first two passes each found once survives in **`if/elsif[/else]`
chains**. The `elsif` clause desugars to a nested `If` whose post-construct `Region` is published
via `update_control_head` (`Actions.pm:2881`) **inside the enclosing `IfStatement`'s parse**. The
outer `IfStatement` action then reads `$ctx->control_head` at construction (`Actions.pm:2718`) and
picks up that leaked Region as its control predecessor instead of the preceding statement. The
Block control-chain rebuild is the only writer that later re-threads the outer `If`'s `inputs[0]`
to the correct chain tail. With the rebuild OFF, the outer `If.control_in` points at the elsif's
nested Region, which orphans the statement preceding the `if` from the scheduler's Return-chain
walk and produces structurally-broken / duplicated codegen.

This is **not synthetic-only**: **18 of the lib/ source files use `elsif`**, and a real one —
`lib/Chalk/Grammar/BNF/Actions.pm` — produces **divergent schedule-driven codegen ON vs OFF**
(confirmed end-to-end below). The 16-file golden set contains **zero** `elsif` files, which is
exactly why the prior pass's 16/16 real-file ON==OFF check passed while this construct was broken —
the identical coverage-gap mechanism that hid the postfix and C-`for` blockers.

A **fourth divergence** (lower reach, but still fails the deletion oracle): a C-style `for` loop
whose init is a **bare assignment** (`for ($i = 0; ...)`, init is an `Assign`, not a `my`-VarDecl)
diverges ON vs OFF. The e5b71467 fix only re-threads when `$init isa VarDecl` (`Actions.pm:3195`);
a non-VarDecl init is not covered. Reach is low (no lib/ for-loop uses a bare-assign init today),
but ON and OFF disagree, so deletion is unsafe for it too.

The secondary caveat from pass 2 (ungated `merge()`/`merge($start)` calls intermixed with the gated
rewrites) is **unchanged and unresolved** — re-stated in Dimension 4.

---

## Summary

| Category | Count |
|---|---|
| Confirmed deletion blockers (this pass) | **1 NEW** (`if/elsif` outer-If control leak) |
| Additional ON==OFF divergence (lower reach, still blocking) | 1 (C-`for` with bare-assign init) |
| Prior blockers re-confirmed RESOLVED | 2 (postfix-modifier; C-`for` with `my`-VarDecl init) |
| Non-blocking caveats for the deletion plan | 1 (ungated `merge()` calls — unchanged from pass 2) |
| `control_in`/`control()` reader sites inventoried | 11 distinct (unchanged; line numbers shifted by the fix commits) |
| Category (c) blocking readers | 0 (unchanged) |
| Synthetic shapes schedule+codegen ON==OFF | 34/36 OK, 2 DIFF, 2 grammar-NOPARSE (both modes) |
| Real-file schedule-codegen ON==OFF | 19/20 SAME, **1 DIFF** (`Grammar/BNF/Actions.pm`, an `elsif` file) |
| Gate suites at HEAD (rebuild ON) | control-threading 50/50, byte-compat-schedule 19/19, control-uniform 14/14 |

**Oracles used:**
- **Differential oracle** — rebuild-ON scheduled output + generated Perl is the oracle for rebuild-OFF.
  (Valid because deletion-safety is defined as ON==OFF byte equivalence, per the brief.)
- **Internal-invariant oracle** — control-predecessor identity (stmt N+1's chain predecessor must be
  stmt N); data-position nodes carry `control_in=undef`.
- **External oracle** (regression guard only) — `control-threading.t`, byte-compat goldens.

---

## Dimension 1 — prior two blockers re-confirmed resolved

**Oracle:** differential + internal-invariant.

control_in chains (ON vs OFF), via parsed method body:

```
postfix-if    (leading vardecl):  ON [0]VarDecl<-Start [1]If<-VarDecl   OFF identical
postfix-while (leading vardecl):  ON [1]Loop<-VarDecl                   OFF identical
C-for my-init (leading vardecl):  ON [1]VarDecl(init)<-VarDecl          OFF identical
C-for first stmt (no preceding):  ON init<-Start                        OFF init<-Start (correctly stays)
```

All postfix flavors (if/unless/while/until/for/foreach), postfix chains, postfix-after-control-flow,
and C-`for` with a `my`-init are byte-identical ON==OFF in both control_in and generated code.
`control-threading.t` is 50/50 at HEAD including the C-`for` hoisted-init target (subtests 49-50).
**Both prior blockers: RESOLVED.**

---

## Dimension 2 — broad ON==OFF schedule + codegen equivalence (decisive)

**Oracle:** differential. Method graph compiled BOTH ways via `build_perl_ir_parser` +
`Chalk::Bootstrap::Perl::Target::Perl::_generate_from_schedule` (the same schedule-driven codegen
path the byte-compat-schedule golden gate uses); full generated text byte-compared.

36-shape adversarial synthetic suite (every hoist/nest construct):

```
OK   01-flat            OK   11-pf-if           OK   21-cfor-then-ret   OK   31-cfor-loopcarry
OK   02-while           OK   12-pf-unless       OK   22-two-cfor        OK   32-pf-after-cfor
OK   03-until           OK   13-pf-while        OK   23-cfor-nested     OK   33-stacked-pf
OK   04-cfor            OK   14-pf-until        OK   24-cfor-after-if    OK   34-ternary-stmt
DIFF 05-cfor-nodecl     OK   15-pf-for          OK   25-cfor-after-call  OK   35-do-while
OK   06-foreach         OK   16-pf-foreach      OK   26-cfor-in-if       OK   36-do-until
OK   07-if-block        OK   17-trycatch        OK   27-list-assign      ERR  37-cfor-multivar (NOPARSE both)
DIFF 09-ifelsif         OK   18-bareblock       OK   28-chained-my       ERR  38-cfor-empty-init (NOPARSE both)
OK   08-ifelse          OK   19-nested-blocks   OK   29-my-do
OK   10-unless          OK   20-cfor-first      OK   30-loop-carried
=== OK=34  DIFF=2  ERR(NOPARSE both modes)=2 ===
```

- **DIFF 09-ifelsif** — `if/elsif/else` preceded by `my $a = 1;`. OFF emits a spurious duplicated
  `if ($b) {...} else {...}` block before the correct `if/elsif/else`, dropping the chain. **BLOCKER.**
- **DIFF 05-cfor-nodecl** — `for ($i = 0; ...)` (bare-assign init). ON emits a spurious extra `$i = 0;`
  line; OFF omits it. They disagree → fails the oracle. (Here OFF is arguably *more* correct, but the
  contract is byte equivalence, so any disagreement blocks.)
- **ERR 37/38** — C-`for` with a comma-multi-init / empty-init clause does not parse in either mode;
  a grammar limitation, not a rebuild divergence. Out of scope (same NOPARSE both ways).

Real `lib/` files via the schedule path (16 goldens + 4 `elsif`-using files), ON vs OFF:

```
SAME × 19  (all 16 goldens + Desugar.pm + Bindings.pm + IR/Serialize/JSON.pm)
DIFF ×  1  lib/Chalk/Grammar/BNF/Actions.pm   <-- elsif file, codegen diverges
=== SAME=19  DIFF=1  ERR=0 ===
```

`Grammar/BNF/Actions.pm` OFF reorders/mangles statements around its `elsif` construct
(first divergence at the elsif region; OFF emits the elsif's inner `if/else` ahead of the surrounding
code). **The 16 goldens stay 16/16 because none contain `elsif`** — the coverage gap that hid this.

Note: `Desugar.pm` and `Bindings.pm` use `elsif` yet matched. The divergence requires a statement
*preceding the if/elsif in the same block* that the orphaning drops — the same conditionality as the
two prior blockers (the loss is only observable when there is a left sibling to lose).

---

## Dimension 6 (re-numbered to match priors) — the third blocker, isolated

**Oracle:** internal-invariant (outer-If chain predecessor must be the preceding statement) +
differential.

control_in chains, one dimension varied per probe (presence of `elsif`):

```
if-only           OFF [1]If<-VarDecl#0      OK   (matches ON)
ifelse-only       OFF [1]If<-VarDecl#0      OK   (matches ON)
nested-if-inelse  OFF [1]If<-VarDecl#0      OK   (nested if INSIDE an else block — Block-wrapped, no leak)
elsif-2arm        OFF [1]If<-Region#2       WRONG (ON: If<-VarDecl#0)
elsif-3arm        OFF [1]If<-Region#2       WRONG (ON: If<-VarDecl#0)
elsif-first       OFF [0]If<-Region#1       WRONG (ON: If<-Start)
```

The discriminating dimension is **`elsif`**. Plain `if`, `if/else`, and even a block-form `if` nested
inside an `else` body all thread correctly OFF. Only the `elsif` chain breaks.

**Why `nested-if-inelse` is safe but `elsif` is not:** a nested `if` inside an `else` body is parsed
as a statement inside a `Block`. The `Block` action republishes `update_control_head($start)`
(`Actions.pm:1766`) to *suppress* the body's control_head from leaking outward, so the enclosing
statement does not see the inner If's Region. The `ElsifChain` is **not** wrapped at that suppression
boundary — it is a direct sub-rule of `IfStatement` — so its `update_control_head($region)`
(`Actions.pm:2881`) is the live control_head when `IfStatement`'s action reads it.

**Root cause (code-level):**
- `ElsifChain` (`Actions.pm:2813`) builds a nested `If` and, at line 2881, calls
  `$sa->update_control_head($region)` publishing its post-construct Region.
- `IfStatement` (`Actions.pm:2648`) — the enclosing rule, whose action fires AFTER the ElsifChain
  sub-rule — reads `my $control = $ctx->control_head // make('Start')` at line 2718 and builds the
  outer `If` with `control => $control`. At that point `$ctx->control_head` is the **elsif's Region**.
- So OFF: outer `If.control_in == <elsif Region>`. ON: the rebuild's If/Loop branch
  (`Actions.pm:1736-1750`) rewires `inputs[0]` to the chain tail (the VarDecl), fixing it.

**Codegen mechanism (why a leading statement is dropped/duplicated):** the scheduler
(`EagerPinning::schedule`, lines 57-78) walks `Return → Region → head (outer If) → If.control_in`.
With `If.control_in == <elsif Region>`, the walk descends into the elsif's nested Region (line 62-67)
instead of continuing to the leading VarDecl. The VarDecl never enters `@body`; the elsif sub-tree is
scheduled in its place, yielding the duplicated/mis-ordered output observed in shape 09 and in
`Grammar/BNF/Actions.pm`.

**Suggested remediation shape (NOT performed):** same class of fix as 6cdcb15b / e5b71467. Either
(a) have `IfStatement` capture the pre-elsif control_head before the ElsifChain sub-rule clobbers it
(mirroring `_find_pre_init_control_head`, which walks the Context multiply tree to recover the
predecessor that was live before a sub-scope's `update_control_head` fired) and pass it as the outer
If's `control`; or (b) suppress the ElsifChain's outward control_head publication the way `Block`
does (publish the pre-elsif head, not the elsif Region), since the elsif Region is a body-internal
merge point that no enclosing statement should consume as its predecessor. Add an
`elsif`-with-leading-statement ON==OFF case to `control-threading.t` (the loss is only observable
with a left sibling). Preserve Start-exclusion when the `if/elsif` is the first statement.

**Side effects to name:** must not perturb plain `if`/`if-else`/nested-if-in-else threading (already
correct), must keep `then_stmts`/`else_stmts` schedule_data intact, must preserve Region-id
determinism, and must be idempotent under rebuild-ON during the transition.

### Fourth divergence — C-`for` with bare-assign init (lower reach, still blocks)

`05-cfor-nodecl`: `for ($i = 0; $i < 3; $i = $i + 1)` (init is an `Assign`, not `my`-VarDecl).
ON: `[2]Assign<-VarDecl#1`, ON codegen emits a spurious extra `$i = 0;`. OFF: `[2]Assign<-undef`,
no extra line. The e5b71467 fix at `Actions.pm:3195` is gated on `$init isa VarDecl`, so a bare-assign
init is not re-threaded. Reach: no current lib/ for-loop uses a bare-assign init (grep confirmed; the
`for ($x = ...)` hits in `EmitHelpers.pm` are list-assignment comments, not loop inits). Still an
ON==OFF divergence → blocks wholesale deletion until covered or proven unreachable in the 31-file set.

---

## Dimension 3 — control_in / inputs[0] reader inventory (re-confirmed)

**Oracle:** internal-invariant (no ordering reader of `control_in` outside the sanctioned Return-chain
walk; data-position nodes carry `control_in=undef`).

The fix commits touched only `Earley.pm` prediction-seed logic and `ForStatement` (added the
`_find_pre_init_control_head` / `_thread_control_head` helpers near the top of `Actions.pm`); they
introduced **no new control_in reader**. Inventory is unchanged from pass 2 (line numbers shifted by
the added helpers: prior `1105 → 1130`, prior `2391 → 2416`):

| Site | Reads | Category |
|---|---|---|
| `IR/Scheduler/EagerPinning.pm:58,66,71,105,111,123` | chain-walk `control_in`/`inputs[0]` | (a) sanctioned |
| `Actions.pm:121` | `control_in` (defined-guard in `_thread_control_head`) | propagation |
| `Actions.pm:1130` | `control_in` (transitive reachability seed, `defined`-guarded) | reachability seed |
| `Actions.pm:1692,1709,1731-1732,1744` | `control_in`/`inputs->[0]` | the rebuild itself (under audit) |
| `Actions.pm:2416` | `control_in` (init-fold copy) | propagation |
| `IR/Node/VarDecl.pm:27` | `control()` → `control_in` | accessor; used by StructPromotion |
| `Optimizer/StructPromotion.pm:767` | `$stmt->control()` | (c)-shaped but pre-broken, XS path only |
| `IR/Node/If.pm`, `Loop.pm`, `Region.pm` | `control_in()` override → `inputs[0]`/`head` | accessor def |
| `IR/Node.pm:31,97-100` | `$control_in` field + `set_control_in` consumer bookkeeping | accessor def |

**Category (c) blocking readers: 0.** No `$graph->nodes`-iterating reader reads `control_in` for
ordering. The Target/Perl + EmitHelpers reads remain value-position (`->value()`), category (b).

**Data-position undef invariant — CONFIRMED HOLDS (rebuild OFF):**
```
bar(foo()); return 1;  →  Call   control_in=Start    (statement position)
                          Constant control_in=undef  (data position)
                          Return control_in=Call
```
Latent-debt acceptance criterion remains **MET**.

`Optimizer/StructPromotion.pm:767` still builds VarDecl with the pre-Proposal-2 3-input shape
`[control, name, init]` (Finding 3 in pass 1). Unchanged, out of scope, still a StructPromotion-
migration follow-up — recorded so it does not become undocumented drift.

---

## Dimension 4 — what the rebuild does beyond control_in (caveat unchanged)

**Oracle:** plan/code comparison.

The rebuild loop (`Actions.pm:1685-1752`) does five things; gating differs:

| Rebuild action | Gated by `$do_rewrite`? | During-parse equivalent | Deletion-safe? |
|---|---|---|---|
| `set_control_in` on VarDecl/Return/Unwind/Call/Assign/... | yes | lateral-seed + `_thread_control_head` | YES except hoisted bare-init Assign |
| Rewrite If/Loop `inputs[0]` (1744-1748) | yes | postfix Case 2 seed; block-form `entry_ctrl`; C-for `_find_pre_init` | **NO for elsif outer-If; NO for bare-init** |
| `$graph->merge($s)` (1691, 1729) | **NO (ungated)** | `_finalize_body_graph` transitive seed | LIKELY (caveat) |
| `$graph->merge($start)` (1678) | **NO (ungated)** | `$graph->start()` cache scan | LIKELY (caveat) |
| Region-advance `$current_control = $s->region // $s` (1750) | drives gated rewrites | block-form publishes Region at stmt boundary | YES |

`*_stmts` ScheduleMeta arrays (then/else/body/try/catch_stmts) are populated by the If/Loop/TryCatch
actions themselves (e.g. `Actions.pm:2785-2791`, `3165-3173`), **not** by the rebuild — disabling the
rebuild does not touch them. Re-confirmed.

**Caveat (non-blocking, unchanged from pass 2):** the three `merge()` calls run UNCONDITIONALLY; the
rebuild-OFF toggle exercises only the absence of *rewrites*, not the absence of the *merges*. All
rebuild-OFF probes in this audit ran with those merges active. `_finalize_body_graph` re-seeds the
graph transitively (`Actions.pm:1085-1135` region), and `Graph::nodes()` checks both id-key and
content_hash-key membership, so a node seeded either way is visible — empirically every top-level
statement is in-graph and `$graph->start()` is defined OFF. But this audit cannot prove the merges
redundant in isolation without editing `lib/`. The deletion plan must either retain the three ungated
`merge`/`merge($start)` calls as a thin hygiene loop, or add an isolated test that neutralizes them
and confirms graph membership.

---

## Dimension 5 — test coverage for deletion

**Oracle:** external (regression guard).

Sole test using the toggle: `t/bootstrap/control-threading.t` (50 subtests at HEAD, all green). Its
ON==OFF suite now covers flat / mixed / call-seq / loop / nested-block / if-else-join, all postfix
flavors, and the C-`for` `my`-init hoist. **It does NOT cover `if/elsif`** and **does NOT cover
C-`for` with a bare-assign init** — exactly the two gaps that let this pass's blocker hide, the same
mechanism that hid the postfix gap (pass 1) and the C-`for` gap (pass 2).

Control-flow shapes still NOT covered by an ON==OFF `.t` assertion (would not catch a deletion
regression): `if/elsif[/else]` (the new blocker), C-`for` bare-init, try/catch, nested-loop,
loop-then-if, postfix-after-control-flow, postfix-chain, bare block.

**Tests requiring rewrite on deletion:** `control-threading.t` parses BOTH ways via the toggle. After
deletion the toggle API (`disable/enable_control_rebuild`, `Actions.pm:91-94`) disappears, so every
rebuild-ON oracle block and the `chain_for($src, 1)` / `chain_for($src, 0)` ON==OFF comparisons must be
re-expressed against fixed golden expectations (the during-parse chain becomes the sole truth). Same
migration shape as the C3 `control-input.t` precedent.

---

## Acceptance-criteria verification

- **Latent-debt criterion** (no ordering reader of `control_in` outside the Return-chain walk;
  data-position nodes carry `control_in=undef`) — **MET** (Dimension 3, unchanged).
- **Postfix blocker resolved** — **MET** (Dimension 1; all flavors ON==OFF).
- **C-`for` `my`-init blocker resolved** — **MET** (Dimension 1; ON==OFF; `control-threading.t` 49-50).
- **Broader idempotence (rebuild redundant for EVERY case)** — **NOT MET.** `if/elsif` outer-If
  control leak diverges (Dimension 6), confirmed at control_in, synthetic schedule-codegen, and
  real-file (`Grammar/BNF/Actions.pm`) levels. C-`for` bare-assign init also diverges. Ungated
  `merge()` calls remain an unverified-in-isolation caveat (Dimension 4).

---

## Deletion plan (YELLOW path — executable once ALL blockers clear)

Deletion is safe to execute only after these prerequisites land:

**Prerequisite A — fix the `if/elsif` outer-If control leak** (remediation in Dimension 6). Add an
`elsif`-with-leading-statement ON==OFF case (2-arm and 3-arm, plus elsif-as-first-statement) to
`control-threading.t` that passes rebuild-OFF.

**Prerequisite B — fix (or prove unreachable) the C-`for` bare-assign init divergence.** Either extend
the e5b71467 re-threading to cover a non-VarDecl init (`Assign`), or confirm via the 31-file
self-hosting sweep that no for-loop uses a bare-assign init and document the restriction. Add a
bare-init C-`for` ON==OFF case to `control-threading.t` if the construct is to be supported.

**Prerequisite C — resolve the ungated-`merge()` caveat** (Dimension 4): either (i) confirm via an
isolated probe that `_finalize_body_graph`'s transitive seeding leaves every top-level statement and
the Start node in `$graph->nodes()` with the rebuild's `merge`/`merge($start)` neutralized, or
(ii) plan to retain those three `merge` calls as a small unconditional graph-hygiene loop.

Then, in order:
1. Re-run the 36-shape synthetic schedule+codegen ON==OFF probe — require 0 DIFFs (currently 34/36,
   2 NOPARSE-both grammar limits; elsif and bare-init C-`for` must reach OK).
2. Re-run the real-file ON==OFF probe over the 16 goldens **plus all 18 `elsif`-using lib/ files** —
   require 0 DIFFs (currently 1 DIFF: `Grammar/BNF/Actions.pm`).
3. Widen to all 31 self-hosting source files; require 0 DIFFs. Watch the `elsif` files and the
   C-`for`-using files (`StructPromotion.pm`, `EmitHelpers.pm`, `Actions.pm`).
4. Add the missing ON==OFF regression cases to `control-threading.t`: `if/elsif[/else]`,
   C-`for` bare-init, try/catch, nested-loop, loop-then-if, postfix-after-control-flow, postfix-chain.
5. Delete the rebuild block. Exact removals:
   - `Actions.pm` lines **1644-1752** (the comment block + `for my $i (0..$#stmts)` rewrite loop) —
     but per Prerequisite C, KEEP the ungated `$graph->merge($start)` (1678) and the per-node
     `$graph->merge($s)` calls (1691, 1729) as a hygiene loop unless proved redundant.
   - The toggle API: `Actions.pm` lines **91-94** (`$_control_rebuild_enabled`, `disable_control_rebuild`,
     `enable_control_rebuild`, `control_rebuild_enabled`).
   - Any `$do_rewrite` references that become dead (1684, 1693, 1710, 1730, 1745).
   - The `_thread_control_head` helper (119-124) and `_find_pre_init_control_head` (134-149) are NOT
     dead — they are the during-parse channel; KEEP them.
6. Rewrite `control-threading.t`: remove every `disable_control_rebuild`/`enable_control_rebuild` call
   and re-express the `chain_for(..., 1)` rebuild-ON oracle and the ON==OFF assertions as comparisons
   against fixed golden expectations (the during-parse chain becomes the sole truth). Same migration
   shape as the C3 `control-input.t` precedent.
7. Re-baseline `t/fixtures/codegen-goldens/*.pl.golden` rebuild-OFF (should be byte-identical to ON).
8. Independently address the StructPromotion VarDecl-shape pre-existing bug (Proposal-2 follow-up) —
   orthogonal, do not leave as drift.

**Gate set to re-run green after deletion:** `t/bootstrap/control-threading.t`,
`t/bootstrap/mop/codegen-byte-compat.t`, `t/bootstrap/mop/codegen-byte-compat-schedule.t`,
`t/bootstrap/control-uniform-representation.t`, plus the `cfg-loop*.t` / `cfg-if-else.t` /
`cfg-try-catch.t` suites and the bnf-target-c determinism assertions cited in 6cdcb15b.

---

## Recurring-pattern note

Three passes, three blockers, all the same shape: a control-flow node constructed mid-statement or in
a sub-scope whose published control_head leaks to an enclosing statement's predecessor, fixed only by
the rebuild. Each was hidden by the same coverage gap — the ON==OFF suite (synthetic and golden) did
not include the offending construct. The constructs that publish `update_control_head` from a position
consumed by an enclosing-statement action are the candidate set:

- `ElsifChain` (2881) — **the pass-3 blocker** (consumed by enclosing `IfStatement`).
- Hoisted for-init VarDecl via `update_control_head` (the VarDecl action publishing inside the
  for-paren) — pass-2 blocker, fixed; bare-assign init variant **still open** (Dimension 6).
- Postfix If/Loop reading `control_head` mid-statement — pass-1 blocker, fixed.

Before any GREEN verdict, the ON==OFF suite must be widened to **every** statement-position construct
that hoists or nests a control-flow node — enumerated in Dimension 2's 36-shape list as a starting
set, plus the full 31-file self-hosting sweep — not just the 16-file golden subset. The golden subset
has now demonstrably hidden a blocker on all three passes.

## Cross-references

- `docs/plans/2026-06-04-rebuild-deletion-readiness-audit.md` — pass 1 (postfix blocker, resolved).
- `docs/plans/2026-06-04-rebuild-deletion-readiness-audit-rerun.md` — pass 2 (C-`for` blocker, resolved).
- `docs/plans/2026-06-02-control-wiring-trio-comparison.md` — execution log; the `if/elsif` outer-If
  leak should be appended to its remaining-work alongside the now-closed postfix and C-`for` items.
- `docs/plans/2026-06-01-merge-and-control-implementation-plan.md` — Phase 2; the elsif leak is the
  same "node constructed/published without the enclosing statement seeing its left sibling" frontier.
- Memory: `block_action_workaround_accretion.md`, `phi_merge_strategy.md` — the ElsifChain Region leak
  is another instance of the mid-statement / sub-scope-node-misses-left-sibling failure mode.
