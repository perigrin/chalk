# If/Else-Join Seed Collision Spike (Capstone Risk Assessment)

**Date:** 2026-06-04
**Branch:** `phase1-lateral-bindings` (HEAD `0fbcffd0`)
**Status:** READ-ONLY investigation. No `lib/` or `t/` edits (`git diff --stat lib/ t/` empty, verified). Probe scripts were ephemeral (`perl -e`), not committed.

## Mandate

Assess the single highest-risk failure mode of the during-parse inherited-control-channel capstone (Proposal 1, `docs/plans/2026-06-02-control-wiring-trio-comparison.md`): the **multi-predecessor seed collision at an if/else join** — the failure class cited as killing the prior during-parse attempt `fb571989`. Produce evidence and a GREEN/YELLOW/RED verdict on tractability.

## TL;DR verdict: **GREEN** (with one mechanical prerequisite already satisfied)

The if/else-join "collision" is **not a collision at the relevant frontier**. The two If/Region pairs the parser builds for an `if/else` are two *different-length spans* completing at *different positions*, not two competing derivations of the same span. The post-if statement (`foo()`) is reached only by the longer span (the one that consumed the `else`), so at `foo()`'s seed frontier there is **exactly one** determinate control predecessor (the with-`else` Region), delivered deterministically. A content-deterministic seed key keyed on `Region->id()` is achievable and collision-free across positions, because Region/If/Proj are counter-id'd (`make_cfg`/ROUTED_CFG), never content-hashed. The two fb571989 failure causes that were *representation* problems (VarDecl identity churn; non-consumption of `control_head`) have since been **remediated** by Proposal 2 (`8c6cfe0f`, `d01bfea3`) and step-(b) (`68218db2`, `a109dcfd`), all of which postdate fb571989.

---

## Q1 — TIMING: is the Region materialized before the post-if statement is predicted?

**Answer: YES. The Region is created strictly before the post-if statement is predicted.**

Probe (parse `class T { method m($self) { if ($c) { $x = 1; } else { $x = 2; } foo(); } }`, wrapping `Chalk::IR::NodeFactory::make` to log If/Region creation and `Chalk::Bootstrap::Earley::_predict` to log statement-rule predictions ≥ char 80; `foo` is at char 85):

```
[seq 0001] FACTORY If       id=If#1
[seq 0002] FACTORY Region   id=Region#4
[seq 0003] FACTORY If       id=If#6
[seq 0004] FACTORY Region   id=Region#9
[seq 0005] PREDICT pos=85 rule=StatementItem
[seq 0006] PREDICT pos=85 rule=SimpleStatement
[seq 0008] PREDICT pos=85 rule=ExpressionStatement
[seq 0009] PREDICT pos=85 rule=CallExpression
```

This is forced by Earley mechanics: `foo()` at char 85 cannot be predicted until the dot advances past the if/else block (chars 40–83), which requires **completing** the `IfStatement` nonterminal — and the `IfStatement` action (which builds the Region, `Actions.pm:2656-2730`) fires on that completion. The completion provides the seed; the Region exists at seed time. **A seed channel can deliver the Region.**

## Q2 — MULTI-PREDECESSOR COLLISION: one determinate predecessor, or several competing?

**Answer: ONE determinate predecessor at `foo()`'s frontier. The apparent "two Regions" are two different-length spans, not competing derivations, and they never reach the same successor position.**

Two probes establish this:

**(2a) The two IfStatement completions are at different end positions:**
```
[seq 0001] COMPLETE IfStatement pos=59 origin=40 focus=If#1 control_head=Region#4
[seq 0002] COMPLETE IfStatement pos=76 origin=40 focus=If#6 control_head=Region#9
```
`pos=59` is the bare `if (...) {...}` (no-else) span; `pos=76` is the `if (...) {...} else {...}` span. They share `origin=40` but end at *different* positions. The no-else completion advances a StatementList item to pos 59; the with-else completion advances a (different) StatementList item to pos 76. `foo()` begins at char 85, reachable only by continuing from pos 76. The pos-59 derivation never reaches `foo()`'s frontier.

**(2b) `add()` NEVER returns two survivors at this frontier — there is no packed ambiguity:**
Instrumenting `SemanticAction::add` to log any 2-survivor return, and `update_control_head` to log every published head:
```
[seq 0001] update_control_head -> Region#4
[seq 0002] update_control_head -> Region#9
```
No `ADD FORK` line was ever emitted. The upstream filtering semirings (Precedence/TypeInference/Structural) leave a single derivation; the two Regions are a deterministic LR fan over distinct spans, not genuine ambiguity surfacing through `add()`'s tie-break. The `add()` tie-break hazard cited for fb571989 does **not** fire here.

**(2c) The merge that advances StatementList copies the IfStatement's head verbatim:**
```
[0001] MUL(L, IfStatement) r.ch=Region#4 => res.ch=Region#4
[0002] MUL(L, IfStatement) r.ch=Region#9 => res.ch=Region#9
```
Each advance carries its own span's Region. A seed placed at the StatementList-advance point would seed the next `StatementItem` prediction at the *corresponding position* — the pos-76 advance seeds at pos~76, reaching `foo()`; the pos-59 advance seeds a (dead-ended) item at pos~59. **No two heads compete for `foo()`'s seed.**

**Final-tree confirmation** (the surviving statements after a full parse):
```
== rebuild ON ==
  stmt op=If    id=If#6   control_in=Start
  stmt op=Call  id=Call|...name=foo... control_in=Region#9
== rebuild OFF ==
  stmt op=If    id=If#6   control_in=Start
  stmt op=Call  id=Call|...name=foo... control_in=Start
```
Rebuild-ON resolves `foo()`'s control_in to **Region#9** (single, determinate). Rebuild-OFF leaves it at the bare **Start** seed — this is the lateral seed gap, and it is the *only* difference. (Note: the If statement's own control_in is `Start` in both — the first-statement-in-block case, correct.)

**Nested if/else** holds the same single-predecessor property. For an `if/else` whose then-branch contains another `if/else`, the outer body's trailing statement resolves to the *outer* Region:
```
update_control_head ids: Region#4, Region#9, Region#14, Region#19
outer body:
  op=If    id=If#16   control_in=Start
  op=Call  id=Call    control_in=Region#19   # after() -> outer Region, single
```

## Q3 — DETERMINISM: would a `node->id()`-keyed seed collide for two identical if/else blocks?

**Answer: NO. Region/If/Proj get per-position counter ids (`Region#9`, `Region#19`), never content-hash ids — so structurally-identical blocks at different positions are distinct, and the seed key is byte-deterministic across runs.**

`Chalk::IR::NodeFactory` (`lib/Chalk/IR/NodeFactory.pm:212-221`): `If`, `Proj`, `Region`, `Phi`, `Loop` are in `%ROUTED_CFG` and allocated via a monotonic `$cfg_counter` (`"${op_name}#${cfg_counter}"`). They are **not** content-hashed. This is the structural opposite of the VarDecl landmine (Proposal 2 step 2): VarDecl *was* content-hashed and required explicit per-position counter identity to avoid two identical `my $x=1` colliding; Region never had that problem.

Probe (two structurally-identical if/else blocks in one method, parsed twice):
```
run1: If<-Start | Call(foo)<-Region#9  | If<-...foo... | Call(bar)<-Region#19
run2: If<-Start | Call(foo)<-Region#9  | If<-...foo... | Call(bar)<-Region#19
DETERMINISTIC across runs: YES
```
`foo()` (after the first if/else) → `Region#9`; `bar()` (after the second) → `Region#19`. Distinct keys, identical across runs. The counter increments in node-creation order, which is parse-order deterministic.

**Codegen-determinism safety:** node ids are analysis-only. `grep '->id'` over `Target/`, `EmitHelpers.pm`, and `Scheduler/` returns nothing — ids never reach emitted output (matches the VarDecl-id finding in the Proposal-2 record). So even though the *unrelated* `_mul_ctx` cache key is still `refaddr:refaddr` (`SemanticAction.pm:124`), that does not leak into codegen; the seed-key determinism the capstone needs rides on `Region->id()`, which is content-deterministic. A `one_with_control($node)` keyed on `node->id()` (as Proposal 1 specified) is achievable here. (`one_with_control` does not yet exist in the tree — consistent with this being design-stage.)

## Q4 — WHY fb571989 failed, and what changed since

fb571989 (`test(control): pin during-parse control predecessor gap (Phase 2 Step A)`, **2026-06-01 22:57**) is in HEAD's history but is a *diagnostic/TODO-pinning* commit, not a landed fix. Its own message states the seed-at-prediction prototype was non-viable for **three** reasons (quoted from `git show fb571989`):

1. *"the bare/refined VarDecl identity split plus the add() tie-break delivers the pre-init head"* — VarDecl carried control in its hash-cons **key** (`inputs[0]`), so the init-fold's bare→refined rebuild plus `add()` tie-break let the next sibling inherit the pre-init head.
2. *"non-VarDecl statements never read control_head into inputs[0] (rebuild-dependent)"* — Call/Assign/etc. actions did not consume `control_head` at construction at all.
3. *"the seed regressed mop/build-graph-reachability.t for if/else"* — the if/else-join case (this spike's target).

**Crucially, two of the three causes have been remediated AFTER fb571989** (timeline verified via `git merge-base --is-ancestor`, all IN-HEAD):

| commit | date | effect |
|---|---|---|
| `fb571989` | 2026-06-01 22:57 | the failed attempt (diagnostic only) |
| `68218db2` | 2026-06-02 20:05 | step-(b): side-effect actions consume `control_head` at construction → **fixes cause 2** |
| `8c6cfe0f` | 2026-06-02 21:48 | Return/Unwind control off `inputs[0]` |
| `d01bfea3` | 2026-06-02 22:04 | VarDecl control off `inputs[0]` + per-position identity → **fixes cause 1** (the bare/refined churn + tie-break landmine) |
| `a109dcfd` | 2026-06-04 00:06 | thread `control_in` at the statement boundary, not sub-expression |

So fb571989 attempted to fix (a)+(b)+(c) simultaneously on a representation where (c) was a determinism landmine — exactly the "wrong order" diagnosis in the trio comparison (`2026-06-02-control-wiring-trio-comparison.md:42`). Causes 1 and 2 are now structurally gone. The action layer already threads control: `Actions.pm:369` routes every statement-position node through `_thread_control_head($ctx, $node, $factory)`, which sets `control_in = $ctx->control_head // Start`. The *only* remaining piece of the if/else case is cause 3 — and this spike shows cause 3 is not a genuine collision (Q2): it was conflated with the cause-1/cause-2 churn that has since been removed.

**The residual gap is purely the seed value.** With the rebuild OFF, `$ctx->control_head` at `foo()`'s action is still `Start` (control-threading.t test 7/9 confirm statement-position Calls consume `control_head`, which is currently `Start`). If `_predict`/the StatementList-advance delivered `Region#9` as the seeded `control_head`, the *existing* `_thread_control_head` call would stamp `control_in=Region#9` during parse, reproducing the rebuild's result.

## Q5 — VERDICT: **GREEN**

The if/else-join collision is **tractable** — in fact it is not a collision at the seed frontier at all:

1. **Timing (Q1):** the Region is materialized before the post-if statement is predicted. ✔
2. **Single predecessor (Q2):** the two If/Region pairs are different-length spans completing at different positions; `foo()` is reached only by the with-else span and sees exactly one head (Region#9). `add()` never forks at this frontier. Holds for nested if/else too. ✔
3. **Determinism (Q3):** Region ids are per-position counter ids, distinct across positions and byte-identical across runs; never reach codegen output. A `node->id()`-keyed seed is collision-free. ✔
4. **Prerequisites (Q4):** the two representation-level causes that doomed fb571989 (VarDecl identity churn; action-layer non-consumption) are already remediated on this branch. The action layer already threads `control_head` into `control_in` at the statement layer. ✔

### Recommended next step

Proceed to a **TDD implementation spike** for the seed channel, scoped narrowly:

- **Seed point:** the StatementList-advance in `_complete` (where `multiply(waiting_value, completed_value)` advances the `StatementList _ . StatementItem` dot). Seed the *next* predicted `StatementItem` at that position with the completing item's `control_head`, via a content-deterministic `one_with_control($node)` keyed on `$node->id()` (NOT refaddr). This covers Program + every Block boundary structurally (one rule), per Proposal 1.
- **Differential oracle:** keep the `disable_control_rebuild`/`enable_control_rebuild` toggle (fb571989) and assert the rebuild-OFF chain is byte-identical to the rebuild-ON chain for the if/else case first, then the flat/nested/loop cases. Convert the Step A TODO in `control-threading.t` once green.
- **Gate set (do NOT under-scope — Proposal-2 B1 lesson):** the full `mop/*` build-graph suite (especially `build-graph-ifelse-*.t`, `build-graph-reachability.t`, `build-graph-control-chain.t`), `bnf-target-c.t` byte-identical ×2, `mop/codegen-byte-compat.t` 19/19, plus the IR-unit and struct-promotion suites that hand-construct nodes. A representation/seed change ripples into every test that builds nodes by hand.
- **Do the loop case as a separate frontier** before declaring the rebuild deletable — Loop also advances via `$s->region` (`Actions.pm:1701`); this spike only fully characterized if/else. The Loop region-advance is the same shape (Q3 confirms Loop is also counter-id'd) but warrants its own differential check.

**Falsification note (what would turn this YELLOW/RED):** if, on a real grammar fragment, two *equal-length* if/else derivations of the same span survive filtering and reach the same successor position carrying different Regions, the single-predecessor property breaks. No such case appeared in flat or nested probes here, but the implementation spike's first RED test should be a deliberate attempt to construct one (e.g. an if/else whose two arms produce the same span end and feed `add()`); if it forks, the seed must defer to the post-`add()` survivor's head rather than seed eagerly per-derivation.

## Appendix: evidence integrity

- `git diff --stat lib/ t/` empty at completion (verified, exit 0; `git status --short` clean).
- Baseline tests confirmed green before analysis: `build-graph-ifelse-phi.t` (7/7), `build-graph-reachability.t` (12/12), `build-graph-control-chain.t` (14/14; the line-148 uninit-value is a pre-existing test-side diagnostic warning, not a failure), `control-threading.t` (10/10; the Step A TODO target is the deeper goal, intentionally still TODO).
- All probes used `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib -It/bootstrap/lib` with `parse_perl_source` from `TestPipeline`.
