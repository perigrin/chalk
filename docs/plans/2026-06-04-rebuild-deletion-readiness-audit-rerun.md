# Block Control-Chain Rebuild — Deletion-Readiness Audit (RE-RUN)

**Date:** 2026-06-04
**Branch:** phase1-lateral-bindings @ 6cdcb15b (clean tree)
**Auditor role:** read-only. No `lib/` or `t/` modifications. Probes ran in `/tmp` and were deleted.
**Subject:** can the Block control-chain rebuild (`lib/Chalk/Bootstrap/Perl/Actions.pm` 1644-1727,
toggled by `disable_control_rebuild`/`enable_control_rebuild`, default ENABLED) now be safely DELETED?
**Predecessor:** `docs/plans/2026-06-04-rebuild-deletion-readiness-audit.md` (VERDICT: RED, single
postfix-modifier blocker).

## VERDICT: RED — one NEW deletion blocker found. The postfix blocker IS resolved.

The postfix-modifier blocker from the prior audit (commit 6cdcb15b) is **fully cleared** — all four
postfix flavors (if/unless/while/until) plus postfix-`for`/`foreach`, postfix-as-first-statement,
postfix-after-call/-if/-loop, and postfix chains are byte-identical ON==OFF, and the
`Chalk::Grammar::Symbol.pm` real-file golden that regressed before now matches (16/16 goldens clean).

**But the same class of bug survives in a different construct the prior audit did not probe:** the
**C-style `for (init; cond; step)` loop hoists its init VarDecl** as a statement-position node
(`ForStatement` returns `[$init, $loop]`, Actions.pm:3160-3165) **whose `control_in` is threaded only
by the Block rebuild.** With the rebuild OFF, the hoisted init VarDecl's `control_in` is `Start`
instead of the preceding statement, which orphans every statement before the `for` loop from the
scheduler's Return-chain walk. A leading `my $r = 0;` is dropped from codegen — identical failure mode
to the original postfix bug, different trigger.

C-style `for` loops are present in real `lib/` source (`StructPromotion.pm`, `EmitHelpers.pm`,
`Actions.pm`), so this is not a synthetic-only edge. They are simply absent from the 16-file golden
set, which is why the golden suite passes 16/16 while the construct still diverges.

A secondary (non-blocking) caveat: the rebuild loop intermixes **gated rewrites** (`$do_rewrite`-
conditional `set_control_in`) with **ungated graph hygiene** (`$graph->merge($start)`,
`$graph->merge($s)`, region-advance). The rebuild-OFF toggle exercises only the *absence of rewrites*;
it does **not** exercise the absence of the merges. Wholesale deletion of 1644-1727 removes both. The
deletion plan must treat the ungated merges separately (keep them, or prove `_finalize_body_graph`'s
transitive seeding subsumes them).

---

## Summary

| Category | Count |
|---|---|
| Confirmed deletion blockers (this re-run) | 1 NEW (C-style `for`-loop hoisted-init control threading) |
| Prior blockers now RESOLVED | 1 (postfix-modifier control threading — all flavors) |
| Non-blocking caveats to handle in the deletion plan | 1 (ungated `merge()` calls in the rebuild loop) |
| `control_in`/`control()` reader sites inventoried | 11 distinct (unchanged from prior audit) |
| Category (c) blocking readers | 0 (unchanged) |
| Synthetic shapes schedule+codegen ON==OFF | 20/20 (incl. all postfix flavors) |
| Loop shapes codegen ON==OFF | 5/6 — C-style `for` DIFFERS |
| Real-file goldens schedule-codegen ON==OFF | **16/16** (Symbol.pm now matches) |
| Gate suites at HEAD (rebuild ON) | control-threading 47/47, byte-compat 19/19, byte-compat-schedule 19/19, control-uniform 14/14 |

---

## Dimension 1 — Postfix blocker now cleared? YES.

**Oracle:** internal-invariant (control predecessor identity: stmt N+1's `control_in` must be stmt N)
+ differential (rebuild-ON is the oracle for rebuild-OFF).

control_in probe (`If`/`Loop` predecessor, ON vs OFF), all flavors:

```
== postfix-if    (leading vardecl) ==   ON: [0]VarDecl<-Start [1]If<-VarDecl [2]Return<-Region
                                       OFF: [0]VarDecl<-Start [1]If<-VarDecl [2]Return<-Region
== postfix-unless(leading vardecl) ==   ON: ... [1]If<-VarDecl ...   OFF: ... [1]If<-VarDecl ...
== postfix-while (leading vardecl) ==   ON: ... [1]Loop<-VarDecl ... OFF: ... [1]Loop<-VarDecl ...
== postfix-until (leading vardecl) ==   ON: ... [1]Loop<-VarDecl ... OFF: ... [1]Loop<-VarDecl ...
== postfix-if FIRST stmt (pred=Start)== ON: [0]If<-Start [1]Return<-Region
                                       OFF: [0]If<-Start [1]Return<-Region   (correctly STAYS Start)
== postfix-if non-leading (2 preds) ==  ON: [0]VarDecl<-Start [1]VarDecl<-VarDecl [2]If<-VarDecl ...
                                       OFF: [0]VarDecl<-Start [1]VarDecl<-VarDecl [2]If<-VarDecl ...
```

- Postfix If/Loop now takes the preceding statement as predecessor in BOTH modes (was `<-Start` OFF).
- Postfix-as-first-statement correctly **stays** `If<-Start` in both modes (Start-exclusion guard,
  Earley.pm:723-724/732-733).
- Non-leading postfix threads to the immediately-preceding statement.

Generated code (rebuild OFF) is complete — the leading statement is no longer dropped:

```
class T { method m($self) { my $a = 1; foo() if $c; return $a; } }   # OFF:
    my $a = 1;            # <-- present (was DROPPED in the prior audit)
    if ($c) { foo(); }
    return $a;
```

Postfix chain (`foo() if $c; bar() unless $d;`) rebuild-OFF emits both `my $a=1` and both branches.

**Symbol.pm golden (the prior 1/16 real-file regression):** rebuild-OFF schedule-codegen output is
**byte-identical to `t/fixtures/codegen-goldens/Chalk__Grammar__Symbol.pl.golden`** (probe:
`OFF==golden? YES`). The dropped `my $str = $self->is_terminal() ? "/$value/" : $value;` line is back.

**Full-method schedule identity (EagerPinning, ON vs OFF):** see Dimension 2 — pf-if/-unless/-while/
-until all schedule and codegen identically.

**Postfix blocker resolution statement: RESOLVED.** The fix (Earley.pm Case 2, lines 727-735) seeds
the predecessor `control_head` into the `ExpressionStatement|SimpleStatement → PostfixModifier`
prediction, so the postfix If/Loop is built with the correct predecessor at construction.

---

## Dimension 2 — Full ON==OFF scheduled-output + codegen equivalence (decisive).

**Oracle:** differential (rebuild-ON scheduled output + generated Perl is the oracle for rebuild-OFF).
Method graph scheduled BOTH ways via `Chalk::IR::Scheduler::EagerPinning::schedule`; schedule item
sequence (`kind:form:operation`) AND full `_generate_from_schedule` output diffed.

20-shape synthetic suite — schedule sequence and generated code:

```
OK 01-flat            OK 06-ifelse-join     OK 11-pf-if           OK 16-pf-after-if
OK 02-mixed           OK 07-trycatch        OK 12-pf-unless       OK 17-pf-after-loop
OK 03-callseq         OK 08-loop-then-if    OK 13-pf-while        OK 18-pf-chain
OK 04-loop-carried    OK 09-nested-loop     OK 14-pf-until        OK 19-nested-blocks
OK 05-nested-if       OK 10-loop-var-use    OK 15-pf-after-call   OK 20-pf-in-loop-body
=== sched OK=20/20  code OK=20/20  BAD=0 ===
```

Every shape: `sched_eq=1 code_eq=1`. Postfix-after-control-flow (16/17), postfix chains (18), and
postfix inside a loop body (20) all match.

**Real `lib/` files (16 goldens, schedule-driven `_generate_from_schedule`, ON vs OFF):**

```
SAME × 16 (including Chalk__Grammar__Symbol.pl.golden)
=== totals: SAME=16 DIFF=0 ERR=0 ===
```

The prior audit's lone divergence (Symbol.pm) is gone. **16/16 real-file ON==OFF, 0 DIFF.**

**Loop-shape extension (see Dimension 6) found the one divergence the synthetic suite missed:**
C-style `for (init; cond; step)` DIFFERS — `code_eq=0`. That is the blocker.

---

## Dimension 3 — control_in / inputs[0] reader inventory (re-confirmed).

**Oracle:** internal-invariant (no pass reads `control_in` for ordering outside the sanctioned
Return-chain walk; data-position nodes carry `control_in=undef`).

Reader sites are **unchanged from the prior audit** (11 distinct). No NEW reader was introduced by the
fix (which touches only `Earley.pm` prediction-seed logic, not any control_in reader). Enumerated:

| Site | Reads | Category |
|---|---|---|
| `IR/Scheduler/EagerPinning.pm:58,66,71,105,111,123` | chain-walk `control_in` | (a) sanctioned |
| `Actions.pm:121` | `control_in` (defined-guard in `_thread_control_head`) | propagation |
| `Actions.pm:1105` | `control_in` (transitive reachability seed, `defined`-guarded) | reachability seed |
| `Actions.pm:1667,1684,1706-1707` | `control_in` / `inputs->[0]` | the rebuild itself (under audit) |
| `Actions.pm:2391` | `control_in` (init-fold copy) | propagation |
| `IR/Node/VarDecl.pm:27` | `control()` → `control_in` | accessor; used by StructPromotion |
| `Optimizer/StructPromotion.pm:767` | `$stmt->control()` | (c)-shaped but pre-broken, XS path only |
| `IR/Node/If.pm:25`, `Loop.pm:27`, `Region.pm` | `control_in()` override → `inputs[0]`/`head` | accessor def |

**Category (c) blocking readers: 0.** `ag` sweep for any `$graph->nodes`-iterating reader that reads
`control_in` for ordering returned only comments, no code. The Target/Perl + EmitHelpers reads at
`Perl.pm:877` and `EmitHelpers.pm:2266` are value-position (`->value()`), category (b), not control.

**Data-position undef invariant — CONFIRMED HOLDS (rebuild OFF):**
```
bar(foo()); return 1;   →   outer Call  control_in=Start    (statement position)
                            inner Constant control_in=undef  (data position)
                            outer Return control_in=Call
                            inner Constant control_in=undef
```
No reader chokes on `undef` (site 1105 guards with `defined`; scheduler never visits data-position
nodes). The latent-debt acceptance criterion remains **MET**.

`Optimizer/StructPromotion.pm:766-768` still builds VarDecl with the pre-Proposal-2 3-input shape
`[control, name, init]` (Finding 3 in the prior audit). Unchanged, still out of scope, still a
StructPromotion-migration follow-up — recorded so it does not become undocumented drift.

---

## Dimension 4 — what the rebuild does beyond control_in.

**Oracle:** plan/code comparison (each rebuild responsibility must have a during-parse equivalent for
deletion to lose nothing).

Re-read of `Actions.pm` 1644-1727. The loop does FIVE things; their gating differs:

| Rebuild action | Gated by `$do_rewrite`? | During-parse equivalent | Deletion-safe? |
|---|---|---|---|
| `set_control_in` on VarDecl/Return/Unwind/Call/Assign/... | **yes** (gated) | lateral-seed channel + `_thread_control_head` | YES for non-hoisted nodes; **NO for C-style for-init (Dim 6)** |
| Rewrite If/Loop `inputs[0]` (1719-1723) | **yes** (gated) | postfix: Case 2 seed; block-form: `entry_ctrl` at construction | YES (block + postfix); **for-init VarDecl is the gap** |
| `$graph->merge($s)` (1666, 1704) | **NO** (ungated) | `_finalize_body_graph` transitive `_seed` from returns+schedule | LIKELY (see caveat) |
| `$graph->merge($start)` (1653) | **NO** (ungated) | `$graph->start()` cache scan | LIKELY (see caveat) |
| Region-advance `$current_control = $s->region // $s` (1725) | drives gated rewrites | block-form publishes `region` as control_head at stmt boundary | YES |

`*_stmts` ScheduleMeta arrays (then_stmts/else_stmts/body_stmts/try_stmts/catch_stmts) are populated by
the **If/Loop/TryCatch actions themselves** (e.g. ForStatement at Actions.pm:3140-3148 sets
`for_init`/`for_step`/`body_stmts` on the Loop's `schedule_data`), **not by the rebuild** —
re-confirmed. Disabling the rebuild does not touch them.

**Caveat (non-blocking, must be handled in the deletion plan):** the two `merge()` calls and the
`merge($start)` run UNCONDITIONALLY — the rebuild-OFF toggle does NOT exercise their absence. The
rebuild-OFF probes in this audit ran with those merges still active. `_finalize_body_graph` re-seeds
the graph transitively from `@returns` + schedule data via `inputs()` and `control_in` (Actions.pm
1085-1110) using `_seed` (id-keyed), whereas the rebuild uses `merge` (content_hash-keyed) —
`Graph::nodes()` membership checks BOTH keys (Graph.pm:119-124), so a node seeded either way is
visible. Empirically all top-level statements are `IN-GRAPH` and `$graph->start()` is `defined`
rebuild-OFF. The transitive walk *should* subsume the merges given a correct control_in chain, but
this audit did **not** prove the merges redundant in isolation (cannot, without editing `lib/`). The
deletion plan must either keep the ungated `merge()`/`merge($start)` as a thin hygiene loop, or add an
isolated test that neutralizes them and confirms graph membership.

---

## Dimension 5 — test coverage for deletion.

**Oracle:** external (the test suite as a regression guard).

Sole test using the toggle: `t/bootstrap/control-threading.t` (47 subtests). Its ON==OFF suite now
covers **10 shapes** (flat / mixed / call-seq / loop / nested-block / if-else-join + postfix
if/unless/while/until, shapes 7-10), plus targets 40-47 asserting the postfix If/Loop predecessor edge
directly. The prior audit's postfix gap is **closed**.

**Control-flow shapes still NOT covered by an ON==OFF test (would not catch a regression on deletion):**
- **C-style `for (init; cond; step)`** — the new blocker (Dim 6). NO ON==OFF coverage. This is the gap
  that let the new blocker hide, exactly as the missing postfix case hid the prior one.
- try/catch ON==OFF (passes in probe; no `.t` assertion).
- nested-loop, loop-then-loop, loop-then-if ON==OFF (pass in probe; no `.t` assertion).
- postfix-after-control-flow, postfix-chain, postfix-in-loop-body (pass in probe; no `.t` assertion).

**Tests requiring rewrite on deletion:** `control-threading.t` parses BOTH ways via the toggle. After
deletion the toggle API (`disable/enable_control_rebuild`, Actions.pm 91-94) disappears, so every
rebuild-ON oracle block and the `chain_for($src, 1)` / `chain_for($src, 0)` ON==OFF comparisons must be
re-expressed against fixed golden expectations (the during-parse output becomes the sole truth). Same
migration shape as the C3 `control-input.t` precedent.

---

## Dimension 6 — loop / Phi frontier (re-confirmed) — ONE BLOCKER.

**Oracle:** differential (rebuild-ON codegen is the oracle).

Loop codegen ON vs OFF:
```
OK   foreach        OK   loop-carried     OK   loop-then-loop
OK   loop-var-after OK   nested-loop      DIFF for-cstyle   <-- BLOCKER
```

`while` / `foreach` / nested / loop-carried / loop-then-loop loops are **safe** ON==OFF (block-form
loops thread correctly: the Loop's `entry_ctrl` is the preceding statement at construction, and the
post-loop `region` is published as control_head at the statement boundary).

**Blocker — C-style `for (init; cond; step)` loop, minimal reproduction:**
```perl
class T { method m($self) { my $r=0; for(my $i=0;$i<3;$i=$i+1){ foo(); } return $r; } }
```
```
=== OFF ===                          === ON ===
    my $i = 0;                           my $r = 0;        <-- present ON
    for (my $i = 0; ...) { ... }         my $i = 0;
    return $r;       # my $r=0 DROPPED   for (my $i = 0; ...) { ... }
                                         return $r;
```

control_in chain (ON vs OFF):
```
for-cstyle ON  (4 stmts): [0]VarDecl<-Start  [1]VarDecl<-VarDecl  [2]Loop<-VarDecl  [3]Return<-Region
for-cstyle OFF (4 stmts): [0]VarDecl<-Start  [1]VarDecl<-Start    [2]Loop<-VarDecl  [3]Return<-Region
                                              ^^^^^^^^^^^^^^^^^ WRONG: should be VarDecl[0]
```

**Root cause (code-level):** `ForStatement` (Actions.pm:3020) returns `[$init, $loop]` (line 3165) —
the C-style for-loop's init VarDecl is HOISTED as a statement-position node prepended before the Loop.
The comment at 3160-3162 states it explicitly: *"for the Block fixup pass to thread the init onto the
control chain BEFORE the Loop."* The `$init` VarDecl's `control_in` is never set in `ForStatement`; it
carries whatever the `VariableDeclaration` action assigned at its own fire-time (Start), and the
**Block rebuild is the only writer that re-threads it** to the preceding statement (1668-1672, the
VarDecl branch). The during-parse lateral-seed channel's Case 2 covers `Expression → PostfixModifier`;
it does **not** cover the hoisted for-init VarDecl, which is emitted by the `ForStatement` action's
return value, not via a PostfixModifier prediction. So OFF leaves `$init.control_in=Start`, the
scheduler walks Return→Region→Loop→`Loop.control_in=$init`→`$init.control_in=Start` and terminates
before reaching `my $r=0`, dropping it.

**Reach:** C-style `for(my $i=...)` loops exist in real `lib/` files — `StructPromotion.pm`,
`EmitHelpers.pm`, `Actions.pm` (grep confirmed). Not in the 16 goldens (hence 16/16), but in scope for
the 31-file self-hosting target. **Loops are NOT fully safe: C-style `for` is a blocker.**

---

## Suggested remediation shape for the new blocker (NOT performed)

Same class of fix as commit 6cdcb15b. Teach the during-parse channel to deliver the preceding
statement's `control_head` to the hoisted for-init VarDecl at construction, OR have `ForStatement` set
`$init->set_control_in($control)` (the `$ctx->control_head` it already reads at line 3070) before
returning `[$init, $loop]` — mirroring how block-form `entry_ctrl` is threaded. Either way the init
VarDecl must take the statement preceding the `for` as its control predecessor, idempotent under
rebuild-ON (Start-exclusion preserved when the `for` is the first statement). After the fix, add a
C-style-`for` ON==OFF case to `control-threading.t` (with a leading statement, to make the loss
observable), and re-run the loop probe to require 0 DIFFs.

**Side effects to name:** the fix must not perturb the block-form `while`/`foreach` threading (which is
already correct) and must keep the `for_init`/`for_step`/`body_stmts` schedule_data intact. Region-id
determinism must be preserved.

---

## Acceptance-criteria verification

- **Latent-debt criterion** (no ordering reader of `control_in` outside the Return-chain walk;
  data-position nodes carry `control_in=undef`) — **MET** (Dimension 3, unchanged).
- **Postfix blocker resolved** — **MET** (Dimension 1; all flavors byte-identical ON==OFF; Symbol.pm
  golden matches; 16/16 real files).
- **Broader idempotence (rebuild redundant for EVERY case)** — **NOT MET.** C-style `for`-loop hoisted
  init VarDecl diverges (Dimension 6), confirmed at control_in, scheduled-codegen, and minimal-repro
  levels. Ungated `merge()` calls are an additional unverified-in-isolation caveat (Dimension 4).

---

## Deletion plan (YELLOW path — executable once the blocker is cleared)

Deletion is safe to execute only after BOTH prerequisites land:

**Prerequisite A — fix the C-style `for`-loop hoisted-init control threading** (remediation above), and
add a C-style-`for` ON==OFF case (leading statement present) to `control-threading.t` that passes
rebuild-OFF.

**Prerequisite B — resolve the ungated-`merge()` caveat:** either (i) confirm via an isolated probe
that `_finalize_body_graph`'s transitive seeding leaves every top-level statement and the Start node in
`$graph->nodes()` with the rebuild's `merge`/`merge($start)` calls neutralized, or (ii) plan to retain
those three `merge` calls as a small unconditional graph-hygiene loop when the rewrite logic is removed.

Then, in order:

1. Re-run the synthetic 20-shape schedule+codegen ON==OFF probe and the loop probe — require 0 DIFFs
   (currently 20/20 synthetic, 5/6 loop; the C-style `for` must reach OK).
2. Re-run the 16-golden real-file ON==OFF probe — require 16/16 (currently 16/16).
3. Widen the real-file ON==OFF check to all 31 self-hosting source files (the goldens are a subset);
   require 0 DIFFs. The C-style-`for`-using files (`StructPromotion.pm`, `EmitHelpers.pm`, `Actions.pm`)
   are the ones to watch.
4. Add the missing ON==OFF regression cases to `control-threading.t`: C-style `for`, try/catch,
   nested-loop, loop-then-if, postfix-after-control-flow, postfix-chain (per the Dim 5 gap list).
5. Delete the rebuild block. Exact removals:
   - `Actions.pm` lines **1644-1727** (the `for my $i (0..$#stmts)` rewrite loop) — but per
     Prerequisite B, KEEP the ungated `$graph->merge($start)` (1653) and the per-node `$graph->merge($s)`
     calls (1666, 1704) as a hygiene loop unless (i) proved them redundant.
   - The toggle API: `Actions.pm` lines **91-94** (`$_control_rebuild_enabled`, `disable_control_rebuild`,
     `enable_control_rebuild`, `control_rebuild_enabled`).
   - Any `$do_rewrite` references that become dead (1659, 1668, 1685, 1705, 1720).
6. Rewrite `control-threading.t`: remove every `disable_control_rebuild`/`enable_control_rebuild` call
   (lines 61/63, 86/88, 119/121, 153/155, 221/223, 286/288, 352/354, 423/425, 473/475, 660/662) and
   re-express the `chain_for(..., 1)` rebuild-ON oracle and the ON==OFF `is($off, $on, ...)` assertions
   as comparisons against fixed golden expectations (the during-parse chain becomes the sole truth).
7. Re-baseline `t/fixtures/codegen-goldens/*.pl.golden` rebuild-OFF (they should be byte-identical to
   the ON goldens — confirmed today for all 16).
8. Independently address the StructPromotion VarDecl-shape pre-existing bug (Actions/StructPromotion
   Proposal-2 follow-up) — orthogonal, do not leave as drift.

**Gate set to re-run green after deletion:** `t/bootstrap/control-threading.t`,
`t/bootstrap/mop/codegen-byte-compat.t`, `t/bootstrap/mop/codegen-byte-compat-schedule.t`,
`t/bootstrap/control-uniform-representation.t`, plus the `cfg-loop*.t` / `cfg-if-else.t` /
`cfg-try-catch.t` suites and the bnf-target-c determinism assertions cited in the 6cdcb15b commit.

---

## Cross-references

- `docs/plans/2026-06-04-rebuild-deletion-readiness-audit.md` — prior RED audit; postfix blocker now
  resolved (this re-run), C-style `for` blocker newly surfaced.
- `docs/plans/2026-06-02-control-wiring-trio-comparison.md` — execution log; the C-style `for`-init
  threading gap should be appended to its remaining-work alongside the now-closed postfix item.
- `docs/plans/2026-06-01-merge-and-control-implementation-plan.md` — Phase 2; the hoisted for-init is
  the same "node constructed/returned without seeing its left sibling" frontier as the postfix case.
- Memory: `block_action_workaround_accretion.md`, `phi_merge_strategy.md` — the hoisted for-init
  VarDecl is another instance of the mid-statement-node-misses-left-sibling failure mode.
