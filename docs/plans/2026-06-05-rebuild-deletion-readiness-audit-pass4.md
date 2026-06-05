# Block Control-Chain Rebuild — Deletion-Readiness Audit (PASS 4, decisive)

**Date:** 2026-06-05
**Branch:** phase1-lateral-bindings @ d7070e25 (clean tree)
**Auditor role:** read-only. No `lib/` or `t/` modifications. Probes ran in `/tmp` and were deleted.
**Subject:** can the Block control-chain rebuild (`lib/Chalk/Bootstrap/Perl/Actions.pm` ~1644-1752,
toggled by `disable_control_rebuild`/`enable_control_rebuild`, default ENABLED) now be safely DELETED?
**Predecessors:**
- `docs/plans/2026-06-04-rebuild-deletion-readiness-audit.md` (pass 1 — RED, postfix-modifier blocker)
- `docs/plans/2026-06-04-rebuild-deletion-readiness-audit-rerun.md` (pass 2 — RED, C-`for` `my`-init blocker)
- `docs/plans/2026-06-05-rebuild-deletion-readiness-audit-pass3.md` (pass 3 — RED, `if/elsif` leak + C-`for` bare-init)

All four prior blockers are FIXED (6cdcb15b, e5b71467, f71b4b49, d7070e25) and re-confirmed resolved below.

## VERDICT: RED — a FIFTH blocker exists.

The leak class is **not** structurally closed. A new instance survives in the combination
**`my $x = EXPR postfix-modifier COND;`** — a `my`-declaration whose statement carries a postfix
`if`/`unless`/`while`/`until`/`for`/`foreach` modifier. With the rebuild OFF, the hoisted `my`-decl
VarDecl (the postfix body) **leaks into the enclosing method body's top-level control chain**, so the
scheduler's Return-chain walk visits it as a top-level statement AND it is also emitted inside the
postfix `if` block — the VarDecl is **duplicated** in generated code (and on the first-statement
variant, mis-ordered). The Block rebuild's If/Loop `inputs[0]` rewire is the only writer that excludes
it from the top-level chain.

This is mechanistically distinct from passes 1-4. In those, the **control_in chain itself diverged**
ON vs OFF. Here the synthesized-body `$mm->body` control_in chain reads **identical** ON==OFF
(`[0]VarDecl<-Start [1]If<-VarDecl [2]Return<-Region`), yet the codegen diverges — because the
divergence is in the **scheduler's reverse-walk edge** (`If.control_in`), where OFF points the If at
the hoisted `$b` VarDecl rather than the preceding `$a` VarDecl. A chain-only oracle (the kind
control-threading.t uses for most targets) would NOT catch this; only a scheduled-output / codegen
differential does. The pass-3 commit message's claim that ElsifChain "closes the whole leak class —
not just elsif" is **falsified**: ElsifChain was the last *sub-rule* update_control_head leaker, but
this fifth blocker is a different leak vector — a `my`-decl publishing **itself** as control_head
(VariableDeclaration, `Actions.pm:1900`) which the *postfix-modifier If/Loop* (same StatementItem)
then consumes.

A **real-file divergence** confirms reach beyond synthetic: `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm`
generates divergent schedule-driven codegen ON vs OFF. It is NOT in the 16-golden set (the goldens are
16/16 SAME, again — the same coverage-gap mechanism that hid all four prior blockers). The
StructPromotion divergence did **not** reduce to any of the minimal shapes probed (it is entangled
with that file's pre-existing both-modes-broken codegen), so per anti-pattern-5 it is reported as a
**separate, not-yet-isolated** real-file divergence rather than consolidated with the shape-41 blocker.

The merge caveat (pass 2/3 "secondary caveat") is now **definitively resolved**: the rebuild's ungated
`$graph->merge` calls are **load-bearing** — they add at least one top-level node to `$graph->nodes`
that `_finalize_body_graph`'s transitive seed does not reach. Wholesale deletion must retain a
merge-only hygiene loop. (Dimension 4.)

---

## Summary

| Category | Count |
|---|---|
| Confirmed deletion blockers (this pass) | **1 NEW** (`my`-decl with postfix modifier — codegen duplication) |
| Additional real-file ON==OFF divergence (not minimally isolated) | 1 (`StructPromotion.pm`) |
| Prior blockers re-confirmed RESOLVED | 4 (postfix bare-expr; C-`for` `my`-init; `if/elsif`; C-`for` bare-init) |
| `update_control_head` invocation sites re-classified | 12 (Actions.pm) + 1 definition (SemanticAction.pm) |
| `control_in`/`control()` reader sites inventoried | unchanged; category-(c) blocking readers = **0** |
| Synthetic shapes schedule+codegen ON==OFF | 44/45 OK, **1 DIFF** (shape 41 `my`-decl postfix) |
| Real-file schedule-codegen ON==OFF (16 goldens + 9 construct files) | 24 SAME, **1 DIFF** (`StructPromotion.pm`); goldens **16/16 SAME** |
| Merge-caveat | **RESOLVED — merges are load-bearing, must be kept** |
| Gate suites at HEAD (rebuild ON) | control-threading **58/58**, codegen-byte-compat-schedule **19/19** |

**Oracles used:**
- **Differential oracle** — rebuild-ON scheduled output + generated Perl is the oracle for rebuild-OFF
  (valid because deletion-safety is defined as ON==OFF byte equivalence, per the brief).
- **Internal-invariant oracle** — control-predecessor identity (the top-level chain must contain only
  top-level statements; a postfix body must not appear in the enclosing chain); data-position nodes
  carry `control_in=undef`.
- **External oracle** (regression guard only) — `control-threading.t`, byte-compat-schedule goldens.

---

## The fifth blocker — `my`-declaration with a postfix modifier (isolated)

**Oracle:** differential + internal-invariant.

**Trigger / minimal failing case:**
```perl
class T { method m($self) { my $a = 1; my $b = foo() if $c; return $a; } }
```

**Generated code, ON vs OFF (schedule-driven `_generate_from_schedule`):**
```
=== ON ===                          === OFF ===
    my $a = 1;                          my $a = 1;
    if ($c) {                           my $b = foo();        <-- SPURIOUS top-level duplicate
        my $b = foo();                  if ($c) {
    }                                       my $b = foo();
    return $a;                          }
                                        return $a;
```

**Why a chain-only oracle misses it.** The synthesized body chain reads identical in both modes:
```
ON  body chain:  [0]VarDecl<-Start [1]If<-VarDecl [2]Return<-Region
OFF body chain:  [0]VarDecl<-Start [1]If<-VarDecl [2]Return<-Region   (looks identical)
```
But the scheduler's reverse-walk from the Return (`EagerPinning::schedule`, lines 57-78) reveals the
real edge:
```
ON  reverse walk:  VarDecl($a) -> If
OFF reverse walk:  VarDecl($a) -> VarDecl($b) -> If    <-- $b leaked into the top-level chain
```
The `If.control_in` is `VarDecl($a)` ON but `VarDecl($b)` OFF; `VarDecl($b).control_in` is
`VarDecl($a)`. The `$mm->body` arrayref dump shows `If<-VarDecl` without disambiguating which VarDecl,
which is why a body-arrayref chain probe (as several prior-pass targets used) reads "identical." The
scheduler-driven codegen is the only oracle that exposes it.

**Schedule-item divergence (decisive):**
```
=== ON schedule items ===            === OFF schedule items ===
  stmt     node=VarDecl                stmt     node=VarDecl
  block_open form=if then=[VarDecl]    stmt     node=VarDecl       <-- EXTRA hoisted top-level VarDecl
  stmt     node=VarDecl                block_open form=if then=[VarDecl]
  block_close                          stmt     node=VarDecl
  stmt     node=Return                 block_close
                                       stmt     node=Return
```

**Root cause (code-level):** `my $b = foo() if $c` is parsed as one StatementItem
(`ExpressionStatement → ... PostfixModifier`). The `VariableDeclaration`/`AssignmentExpression` action
that builds the `$b` VarDecl publishes **itself** as control_head (`Actions.pm:1900`
`$sa->update_control_head($var_decl)`, and the init-fold at `:2441`) BEFORE the `PostfixModifier`
action fires. The PostfixModifier `if`/`unless` branch reads `my $control = $ctx->control_head //
make('Start')` (`Actions.pm:2581`; loop forms at `:2488`-equivalent), so the postfix `If` is built
with `control => VarDecl($b)`. The 6cdcb15b postfix fix (Earley Case-2 seed) delivers the *preceding*
statement's control_head into the postfix prediction — but it does not undo the `my`-decl's
self-publication that happens *inside* the same StatementItem. Rebuild ON, the rebuild's If/Loop
branch (`Actions.pm:1744-1748`) rewrites `If.inputs[0]` to the chain tail (`VarDecl($a)`), excluding
`$b` from the top-level walk and leaving it only in `then_stmts`. Rebuild OFF, nothing corrects it.

**Discriminating dimension (one varied per probe):**
```
A-bareexpr-if      foo() if $c;                 OK    (no my-decl in body)
B-mydecl-if        my $b = foo() if $c;         DIFF
C-mydecl-unless    my $b = foo() unless $c;     DIFF
D-mydecl-while     my $b = foo() while $c;      DIFF
E-mydecl-for       my $b = foo() for @x;        DIFF
F-bareassign-if    $b = foo() if $c;            OK    (Assign body does not self-publish before postfix)
G-mydecl-if-first  my $b = foo() if $c;  (first stmt, no leading sibling)  DIFF
```
The trigger is the **`my` (VarDecl) in the postfix body**, across all postfix flavors, and even as the
first statement (G — there the duplication/mis-order still occurs because the hoisted `$b` is walked
as a top-level statement). A bare-expression body (A) and a bare-assignment body (F) are safe — only
a `my`-decl self-publishes as control_head ahead of the postfix node.

**Reach in real `lib/` source:** no current `lib/*.pm` file uses a method-body-level `my`-decl
postfix-modifier statement (a refined grep for `^\s*my \$x = ... if/unless/while/until;` and the
for/foreach variants returns only false positives — `my $sd = $if->schedule_data;`, where `$if` is a
variable, not a postfix `if`). So the *minimal* shape-41 reach is synthetic-only today, like the
pass-3 bare-assign C-`for` blocker (#4). But (a) the contract is ON==OFF for *everything* on the
deletion path, and (b) a related real-file divergence (StructPromotion, below) confirms a residual
leak reaches real code.

**Suggested remediation shape (NOT performed):** same class as 6cdcb15b. Either (a) when a
PostfixModifier's body node is a `my`-decl (or any node that self-published as control_head during this
StatementItem), recover the pre-body control_head — mirroring `_find_pre_init_control_head`, which
already walks the Context multiply tree to recover the predecessor live before a sub-node's
`update_control_head` clobbered it — and build the postfix If/Loop with that predecessor; or (b) have
the StatementItem layer, which already runs the lateral-seed channel, re-thread a postfix-modifier
If/Loop's `inputs[0]` to the arriving control_head when its current control predecessor is the
postfix-body node it encloses. Add `my`-decl-postfix ON==OFF cases (all flavors, with and without a
leading statement, and as first statement) to `control-threading.t` — and make at least one of them a
**codegen/schedule** assertion, not just a `control_in` assertion, since the chain reads identical.

**Side effects to name:** the fix must not perturb bare-expr postfix (already correct) or
bare-assign postfix (correct), must preserve the postfix If/Loop's own `then_stmts` (the body VarDecl
must still emit inside the if block), must keep Start-exclusion for the first-statement case, and must
be idempotent under rebuild-ON during the transition.

### Additional real-file divergence — `StructPromotion.pm` (not minimally isolated)

`lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm` diverges ON vs OFF in schedule-driven codegen. The
divergences cluster around method bodies that mix postfix-modifier statements (`return unless defined
$x;`, `next if $cls->name eq 'main';`, `$mop->set_...($schemas) if keys ...;`) with following
`my`-declarations (`my $var_name = $target->value(); my $var_key = ...;`). The OFF output relocates
the trailing `my`-decls ahead of the postfix-guard blocks and, in one method, resolves a different
`$var_name` binding (`my $var_key = ${var_prefix}::${var_name};` OFF vs the unresolved-string form
ON), consistent with the same hoist/scope leak.

This file is **not** a golden and its codegen is **already broken in BOTH modes** (e.g. OFF emits
`next(if($cls->name())) eq 'main';` — a parse-level mangle present regardless of the rebuild), so the
ON==OFF divergence is entangled with pre-existing breakage. Each minimal shape I extracted to isolate
it — `my`-decl after `return unless` (S1-S4), postfix-in-foreach-body including `my $y = foo() if $x`
(L1-L7), postfix-on-return-not-last (R1-R5) — came back **OK** in isolation. Per anti-pattern-5
(no confidently-wrong consolidation without isolation proof), this is reported as a **separate,
not-yet-reduced real-file divergence**, NOT merged into the shape-41 finding. It is, however, the same
*family* (a self-publishing or sub-rule control_head leaking into an enclosing chain), and it confirms
the leak class still touches real code. Reducing it to a minimal trigger is follow-up work the deletion
plan must complete before GREEN.

---

## Dimension 1 — prior four blockers re-confirmed resolved

**Oracle:** differential. From the 45-shape synthetic suite (Dimension 2):
```
04-cfor-my        OK   (pass-2 blocker, my-init C-for)        — RESOLVED
05-cfor-noassign  OK   (pass-3 blocker #4, bare-assign C-for) — RESOLVED
09-ifelsif        OK   (pass-3 blocker, if/elsif/else)        — RESOLVED
11..16 pf-*       OK   (pass-1 blocker, bare-expr postfix all flavors) — RESOLVED
34-elsif-first    OK   35-double-elsif OK  36-nested-if-in-else OK  23-elsif-in-loop OK  25-cfor-in-elsif OK
```
`control-threading.t` is **58/58** at HEAD (including elsif targets 52-54 and ON==OFF shapes 12-15).
All four prior blockers byte-identical ON==OFF.

---

## Dimension 2 — broad ON==OFF schedule + codegen equivalence (decisive)

**Oracle:** differential. Method graph compiled BOTH ways via `build_perl_ir_parser` +
`Chalk::Bootstrap::Perl::Target::Perl::_generate_from_schedule` (the same schedule-driven codegen path
the byte-compat-schedule golden gate uses); full generated text byte-compared.

**45-shape adversarial synthetic suite** (every hoist/nest construct + the brief's requested nestings):
```
OK 01-flat            OK 13-pf-while         OK 25-cfor-in-elsif    OK 37-cfor-loopcarry
OK 02-while           OK 14-pf-until         OK 26-pf-in-try        OK 38-if-then-if
OK 03-until           OK 15-pf-for           OK 27-nested-try       OK 39-loop-then-if
OK 04-cfor-my         OK 16-pf-foreach       OK 28-my-multi         OK 40-mixed-everything
OK 05-cfor-noassign   OK 17-trycatch         OK 29-chained-my       DIFF 41-mydecl-pf-if  <-- BLOCKER
OK 06-foreach         OK 18-trycatch-after   OK 30-loop-carried     OK 42-bare-assign-seq
OK 07-if-block        OK 19-nested-blocks    OK 31-pf-after-cfor    OK 43-call-seq
OK 08-ifelse          OK 20-cfor-first       OK 32-stacked-pf       OK 44-do-block
OK 09-ifelsif         OK 21-cfor-then-ret    OK 33-ternary-stmt     OK 45-trycatch-then-pf
OK 10-unless          OK 22-two-cfor         OK 34-elsif-first
OK 11-pf-if           OK 23-elsif-in-loop    OK 35-double-elsif
OK 12-pf-unless       OK 24-cfor-in-if       OK 36-nested-if-in-else
=== OK=44  DIFF=1 (shape 41)  OTHER=0 ===
```
Coverage of the brief's explicitly-requested nestings: elsif-in-loop (23), C-for-in-elsif (25),
C-for-in-if (24), postfix-in-try (26), nested-try (27), `my (...)` multi-decl (28), chained ternary
at stmt (33 ternary, plus 41 my-decl), do-block (44), bare block / nested blocks (19), try/catch +
following statement (18, 45), `my $x = ... if ...` (41 — the blocker), postfix-after-control-flow
(31), stacked postfix (32), loop/Phi/back-edge (02/03/30/37). The single divergence is shape 41.

**Real `lib/` files via the schedule path** (16 goldens + 9 tractable construct-bearing files), ON vs OFF:
```
GOLDEN: SAME=16  DIFF=0    (all 16 byte-identical ON==OFF — confirms the prior 16/16)
EXTRA:  SAME=8   DIFF=1
  SAME: Desugar.pm Bindings.pm IR/Serialize/JSON.pm IR/Schedule.pm IR/Schedule/Item.pm
        IR/Node.pm Grammar/Perl/KeywordTable.pm Bootstrap/CoreItemIndex.pm
  DIFF: Bootstrap/Optimizer/StructPromotion.pm   <-- the additional real-file divergence
=== SAME=24  DIFF=1  ASYM=0 ===
```
(The exhaustive all-`lib`/`*.pm` sweep was attempted but OOMs on the large XS/grammar files — known
behavior per MEMORY.md "XS Earley OOM on large files." The construct-bearing subset above targets the
elsif / C-`for` / postfix users that are tractable; the giants are out of reach for a both-modes
parse in this environment and are flagged as residual coverage in the deletion plan.)

The brief's hypothesis that loops/Phi/back-edges might diverge is **not** borne out (02/03/30/37 OK).
`*_stmts` ScheduleMeta arrays are populated by the If/Loop/TryCatch actions themselves, never by the
rebuild — disabling the rebuild does not touch them (re-confirmed; see Dimension 4).

---

## Dimension 3 — `update_control_head` 18-site re-classification

The brief named "18 call sites." At HEAD there are **12 invocation sites in `Actions.pm`** plus the
**1 method definition** in `SemanticAction.pm` (line 260). The "18" is a stale count (prior passes'
greps included comment lines that reference `update_control_head`; the line-grep returns 12 actual
`$sa->update_control_head(...)` invocations). All 12 are enumerated and classified below by the brief's
scheme: **statement-level-publisher** (publishes a Region/node meant to be the predecessor of the
*following sibling statement* — correct and safe) vs **sub-rule-suppressor / mid-statement** (fires
inside a construct consumed by an enclosing action — the leak risk).

| # | Line | Caller | Publishes | Classification | Leak-safe? |
|---|---|---|---|---|---|
| 1 | 388 | `StatementItem` (list-builtin reify) | the merged Call | statement-level publisher | YES — advances chain for next sibling |
| 2 | 419 | `StatementItem` (lateral-seed) | the side-effect node | statement-level publisher | YES — the core lateral channel |
| 3 | 1766 | `Block` | a fresh `Start` (suppression) | **suppressor** | YES — intentionally hides body tail from enclosing action |
| 4 | 1900 | `VariableDeclaration` | the VarDecl (self) | self-publisher | **NO in one case** — leaks when the VarDecl is a *postfix-modifier body* (the fifth blocker); safe as a plain top-level statement |
| 5 | 2441 | `AssignmentExpression` (init-fold) | the refined VarDecl (self) | self-publisher | same caveat as #4 (init-fold path of a `my`-decl) |
| 6 | 2565 | `PostfixModifier` (while/until) | the Loop's Region | statement-level publisher | YES — Region is the predecessor for the next sibling |
| 7 | 2629 | `PostfixModifier` (if/unless) | the If's Region | statement-level publisher | YES — same |
| 8 | 2794 | `IfStatement` (block/elsif/else) | the If's Region | statement-level publisher | YES — outer If publishes its own Region for the next sibling |
| 9 | 2891 | `ElsifChain` | a fresh `Start` (suppression) | **suppressor** | YES — f71b4b49 structural fix; the pass-3 leak vector, now closed |
| 10 | 3028 | `WhileStatement`/`ForeachStatement` | the Loop's Region | statement-level publisher | YES |
| 11 | 3186 | `ForStatement` (C-style) | the Loop's Region | statement-level publisher | YES (init re-threaded separately at 3206-3230, e5b71467+d7070e25) |
| 12 | 3371 | `ForeachStatement` (iterator/list form) | the Loop's Region | statement-level publisher | YES |

**Key result:** the brief's hypothesis — "every sub-rule either publishes Start or is otherwise safe"
— holds for the two genuine *sub-rule* leakers (Block #3 and ElsifChain #9, both publish Start). But
the brief's framing missed a different vector: **self-publishing nodes** (#4 VarDecl, #5 init-fold
Assign-to-`my`). A `my`-decl publishes *itself* as control_head; when that `my`-decl is the **body of a
postfix modifier** (parsed in the same StatementItem as the postfix `If`/`Loop`), the postfix node
(sites #6/#7) reads the self-published VarDecl as its control predecessor. The leak is not a sub-rule
publishing a Region — it is a same-statement self-publication that the postfix node consumes. ElsifChain
was the last *sub-rule* leaker, but it was **not** the last leaker. Sites #4/#5 remain leak vectors in
the postfix-body context.

**`TryCatchStatement` note:** TryCatch (`Actions.pm:1227`) consumes control_head via
`_thread_control_head` but does **not** call `update_control_head` to advance the chain. The statement
following a try/catch therefore does not get the TryCatch as its lateral predecessor — yet shapes 18
(`try {...} catch {...} my $b=2; return $b;`) and 45 (try/catch then postfix) are ON==OFF **OK**,
because `_finalize_body_graph`'s transitive seed + the synthetic-Return control_in resolution reach
the right chain. So this is not a blocker today, but it is the reason the deletion plan must keep the
real-file sweep honest: TryCatch's chain-advance is implicit, not via the lateral channel.

---

## Dimension 4 — what the rebuild does beyond control_in; the merge caveat RESOLVED

**Oracle:** plan/code comparison + empirical graph-membership probe.

The rebuild loop (`Actions.pm:1685-1752`) does five things; gating differs:

| Rebuild action | Gated by `$do_rewrite`? | During-parse equivalent | Deletion-safe? |
|---|---|---|---|
| `set_control_in` on VarDecl/Return/Unwind/Call/Assign/… | yes | lateral-seed + `_thread_control_head` | YES except postfix-body `my`-decl (blocker) |
| Rewrite If/Loop `inputs[0]` (1744-1748) | yes | postfix Case-2 seed; block `entry_ctrl`; C-for `_find_pre_init` | **NO for postfix-body `my`-decl** (the fifth blocker) |
| `$graph->merge($s)` (1691 VarDecl, 1729 Call/Assign/…) | **NO (ungated)** | `_finalize_body_graph` transitive seed | **NO — load-bearing, see below** |
| `$graph->merge($start)` (1678) | **NO (ungated)** | `$graph->start()` cache scan | LIKELY redundant (Start always present in probes) |
| Region-advance `$current_control = $s->region // $s` (1750) | drives gated rewrites | block-form publishes Region at stmt boundary | YES |

**Merge caveat — DEFINITIVE RESOLUTION.** I probed graph membership by computing, independently of the
rebuild's merges, the transitive closure that `_finalize_body_graph` builds (roots = Returns + schedule
CFG nodes; edges = `inputs()` + `control_in`) and checking whether every top-level statement node is in
that closure. Result, ON mode (rebuild rewrites + merges both active):
```
T::a (my $x=1; foo(); $x=2; return $x;)  body=4 nodes=10 start=Y  closure-misses=[VarDecl]
T::b (if/else; while; return)            body=4 nodes=26 start=Y  closure-misses=[]
T::c (C-for; try/catch; return)          body=4 nodes=27 start=Y  closure-misses=[]
```
Method `a`'s closure (Returns + CFG roots, following inputs+control_in) **does not reach one top-level
VarDecl** — yet that VarDecl IS in `$graph->nodes` (10 nodes) **because the rebuild's ungated
`$graph->merge($s)` at line 1691 put it there.** The init-fold path (`AssignmentExpression`, `:2444-2445`)
unmerges the bare VarDecl and merges the refined one, but the refined node's graph membership for the
top-level chain still relies on the rebuild's merge in the cases where the transitive seed misses it
(the closure followed identity/`->id`, and the refined node's id is not always reachable from a Return
via inputs+control_in when its consumer is a later-rebuilt node).

**Conclusion:** the rebuild's per-node `$graph->merge` calls (1691, 1729) are **NOT redundant** with
`_finalize_body_graph`'s transitive seed. Deleting the rebuild wholesale would drop at least one
top-level node from `$graph->nodes` for some methods. **The deletion MUST retain a merge-only hygiene
loop** (iterate top-level statements, `$graph->merge($s)` for each VarDecl/Call/Assign/CompoundAssign/
RegexSubst/TryCatch, `$graph->merge($start)`), stripped of every `set_control_in`/`inputs[0]` rewrite.
The `$graph->merge($start)` at 1678 is plausibly redundant (`$graph->start()` was defined in every
OFF probe), but should be kept in the hygiene loop unless a dedicated isolation test proves it
unnecessary.

`*_stmts` ScheduleMeta arrays (then/else/body/try/catch_stmts) are populated by the If/Loop/TryCatch
actions themselves (e.g. `Actions.pm:2785`, `3020`, `3175`, `1233`), **not** by the rebuild —
re-confirmed; disabling the rebuild does not touch them.

---

## Dimension 5 — control_in / inputs[0] reader inventory (re-confirmed)

**Oracle:** internal-invariant (no ordering reader of `control_in` outside the sanctioned Return-chain
walk; data-position nodes carry `control_in=undef`).

The four fix commits introduced **no new control_in ordering reader**. The only new read is at
`Actions.pm:3226` (`$loop->control_in` inside the d7070e25 C-for init-threading guard) — a writer-side
comparison, propagation category, not an ordering reader. Inventory (line numbers at HEAD):

| Site | Reads | Category |
|---|---|---|
| `IR/Scheduler/EagerPinning.pm:58,66,71,105,111,123` | chain-walk `control_in`/`inputs[0]` | (a) sanctioned |
| `Actions.pm:121` | `control_in` (defined-guard in `_thread_control_head`) | propagation |
| `Actions.pm:1130` | `control_in` (transitive reachability seed, defined-guarded) | reachability seed |
| `Actions.pm:1692,1709,1731-1732,1744` | `control_in`/`inputs->[0]` | the rebuild itself (under audit) |
| `Actions.pm:2416` | `control_in` (init-fold copy) | propagation |
| `Actions.pm:3226` | `control_in` (C-for Loop rewire guard) | propagation (NEW, d7070e25) |
| `IR/Node/VarDecl.pm:27` | `control()` → `control_in` | accessor; used by StructPromotion:767 |
| `Optimizer/StructPromotion.pm:767` | `$stmt->control()` | (c)-shaped but pre-broken, XS path only |
| `IR/Node/If.pm`, `Loop.pm`, `Region.pm` | `control_in()` override → `inputs[0]`/`head` | accessor def |
| `IR/Node.pm:97-100` | `$control_in` field + `set_control_in` consumer bookkeeping | accessor def |

**Category (c) blocking readers: 0.** The four `$graph->nodes`-iterating sites
(`Target/Perl.pm:467` aggregate sigils, `Actions.pm:839` Call-target resolution, `MOP/Class.pm:142`
node collection, `IR/Serialize/JSON.pm:97` serialization) read for sigil/target/membership, **none**
read `control_in` for ordering. Value-position reads (`Perl.pm`, `EmitHelpers.pm`) use `->value()`
(category b). **Data-position undef invariant CONFIRMED HOLDS** (rebuild OFF):
```
bar(foo()); return 1;  →  Call control_in=Start (stmt position); inner Constant control_in=undef (data)
```
Latent-debt acceptance criterion remains **MET**.

`StructPromotion.pm:767` still builds VarDecl with the pre-Proposal-2 3-input shape `[control, name,
init]` (Finding 3 from pass 1). Unchanged, out of scope, still a StructPromotion-migration follow-up —
recorded so it does not become undocumented drift. (Note: this same file is the one whose codegen
diverges ON==OFF; the two issues are independent — one is a WRITE-shape bug, the other a control leak.)

---

## Dimension 6 — test coverage for deletion

**Oracle:** external (regression guard).

Sole test using the toggle: `t/bootstrap/control-threading.t` (58/58 at HEAD). Its ON==OFF suite
covers flat / mixed / call-seq / loop / nested-block / if-else-join, all bare-expr postfix flavors,
C-`for` `my`-init and bare-init, and if/elsif (2-arm, 3-arm, first). It does **NOT** cover:
- **`my`-decl with a postfix modifier** (the fifth blocker) — and critically, even if added as a
  `control_in` assertion it would **pass** (the chain reads identical); it needs a **codegen/schedule**
  assertion.
- try/catch ON==OFF, nested-loop, loop-then-if, postfix-after-control-flow (pass in probe; no `.t`).

**Tests requiring rewrite on deletion:** `control-threading.t` parses BOTH ways via the toggle. After
deletion the toggle API (`disable/enable_control_rebuild`, `Actions.pm:91-94`) disappears, so every
rebuild-ON oracle block and the `chain_for($src, 1)`/`chain_for($src, 0)` ON==OFF comparisons must be
re-expressed against fixed golden expectations (the during-parse output becomes the sole truth). Same
migration shape as the C3 `control-input.t` precedent.

---

## Acceptance-criteria verification (against the brief)

- **Re-enumerate all `update_control_head` call sites, classify publisher vs sub-rule-suppressor** —
  **MET.** 12 sites (not 18; "18" was a stale count). Dimension 3 table; both sub-rule suppressors
  (Block, ElsifChain) publish Start; the residual leak vector is *self-publishing `my`-decls* (#4/#5)
  consumed by postfix nodes, which the brief's sub-rule framing did not anticipate.
- **Statement-position construct returning multiple/hoisted nodes whose non-first predecessor isn't
  threaded OFF** — **FOUND.** `ForStatement` `[init, loop]` is covered (e5b71467/d7070e25); but the
  postfix-modifier `my`-decl hoists its body VarDecl into the chain — the fifth blocker.
- **Deeper nestings / combinations** — TESTED (45 synthetic shapes + the brief's explicit list). Only
  `my`-decl-postfix (41) diverges; elsif-in-loop, C-for-in-elsif/-in-if, postfix-in-try, nested-try,
  do-block, bare/nested blocks, `my (...)` multi, chained ternary, loop/Phi/back-edge all OK.
- **Broad ON==OFF scheduled-output + codegen (40+ synthetic; every compilable real file both ways)** —
  **DONE.** 45 synthetic (44 OK / 1 DIFF); 16/16 goldens SAME + 9 construct files (8 SAME / 1 DIFF
  StructPromotion). Exhaustive all-`lib` sweep OOMs on the giants (documented limitation).
- **control_in reader inventory — still zero category-(c)** — **MET** (Dimension 5).
- **Merge caveat — definitively resolved** — **MET.** Merges are **load-bearing**; deletion must keep
  a merge-only hygiene loop (Dimension 4).
- **Broader idempotence (rebuild redundant for EVERY case)** — **NOT MET.** `my`-decl postfix modifier
  diverges (codegen duplication); StructPromotion.pm diverges (real file, not yet minimally isolated).

---

## Deletion plan (YELLOW path — executable once ALL blockers clear)

Deletion is safe to execute only after these prerequisites land:

**Prerequisite A — fix the `my`-decl postfix-modifier leak** (remediation above). Add ON==OFF
**codegen/schedule** cases (all postfix flavors; with-leading-statement and as-first-statement) to
`control-threading.t`. A `control_in`-only assertion is insufficient — the chain reads identical;
the assertion must compare scheduled output or generated code.

**Prerequisite B — reduce and fix the `StructPromotion.pm` real-file divergence.** Bisect the file to a
minimal trigger (the entangled both-modes-broken codegen must be set aside; isolate the control-leak
component). Likely the same family as A — confirm with isolation probes before consolidating. Add the
reduced shape to `control-threading.t`.

**Prerequisite C — retain the merge-only hygiene loop (Dimension 4 RESOLVED).** When the rewrite logic
is removed, KEEP a loop over top-level statements that does `$graph->merge($s)` for each
VarDecl/Call/Assign/CompoundAssign/RegexSubst/TryCatch and `$graph->merge($start)`. These merges are
load-bearing — the transitive seed in `_finalize_body_graph` does not reach every top-level node.

**Prerequisite D — widen the real-file sweep to the OOM giants.** The construct-bearing subset is
8 files; the full 31-file self-hosting target includes large files that OOM a both-modes parse in this
environment. Run the sweep on a higher-memory host (or per-file with the XS Boolean fast path) to
confirm 0 DIFFs across all 31 before deletion.

Then, in order:
1. Re-run the 45-shape synthetic schedule+codegen ON==OFF probe — require 0 DIFFs (currently 44/45;
   shape 41 must reach OK).
2. Re-run the real-file ON==OFF probe over the 16 goldens + all construct-bearing files (and, per
   Prereq D, the giants) — require 0 DIFFs (currently 24/25; StructPromotion must reach SAME).
3. Add the missing ON==OFF regression cases (codegen-level) to `control-threading.t`:
   `my`-decl postfix (all flavors), try/catch, nested-loop, loop-then-if, postfix-after-control-flow.
4. Delete the rebuild rewrite logic. Exact removals (line numbers at HEAD d7070e25):
   - `Actions.pm` lines **1669-1752** (the comment block + `for my $i (0..$#stmts)` rewrite loop),
     **but per Prerequisite C, REPLACE with a merge-only hygiene loop**: keep
     `$graph->merge($start)` (1678) and the per-node `$graph->merge($s)` (1691, 1729); delete every
     `set_control_in`/`inputs[0]` rewrite and the `$do_rewrite`/`$current_control` machinery.
   - The toggle API: `Actions.pm` lines **91-94** (`$_control_rebuild_enabled`,
     `disable_control_rebuild`, `enable_control_rebuild`, `control_rebuild_enabled`) and the
     `my $do_rewrite = $_control_rebuild_enabled;` at **1684**.
   - **DO NOT delete** `_thread_control_head` (119-124) or `_find_pre_init_control_head` (134-149) —
     they are the during-parse channel and are called by StatementItem and ForStatement
     respectively (confirmed: `_thread_control_head` is called at 385, 405, 1227; `_find_pre_init_control_head`
     at 3214). Both have live non-rebuild callers.
5. Rewrite `control-threading.t`: remove every `disable_control_rebuild`/`enable_control_rebuild` call
   and re-express the `chain_for(..., 1)` rebuild-ON oracle and the `is($off,$on,...)` ON==OFF
   assertions as comparisons against fixed golden expectations (the during-parse chain becomes the
   sole truth). Same migration shape as the C3 `control-input.t` precedent.
6. Re-baseline `t/fixtures/codegen-goldens/*.pl.golden` (should be byte-identical — confirmed 16/16
   today). Independently address StructPromotion's VarDecl WRITE-shape bug (Proposal-2 follow-up;
   orthogonal to the control leak).

**Gate set to re-run green after deletion:** `t/bootstrap/control-threading.t`,
`t/bootstrap/mop/codegen-byte-compat.t` (byte-identical x2 determinism),
`t/bootstrap/mop/codegen-byte-compat-schedule.t`, `t/bootstrap/leo-graph-equivalence.t`,
`t/bootstrap/control-uniform-representation.t`, the bnf-target-c determinism assertions (tests 94,
178), the `cfg-loop*.t`/`cfg-if-else.t`/`cfg-try-catch.t` suites, and the full bootstrap failure set
== baseline (54 files).

---

## Recurring-pattern note

Four passes, four blockers, all "a control-flow node constructed mid-statement or in a sub-scope whose
published control_head leaks to an enclosing statement's predecessor." The fifth is a **variant**: a
`my`-declaration self-publishing as control_head, consumed by a postfix modifier in the *same*
statement — and it manifests not as a control_in chain divergence but as a **scheduled-output /
codegen duplication** while the chain reads identical. The lesson the prior plan drew ("ElsifChain was
the last sub-rule leaker, so the class is closed") was **half right**: the last *sub-rule* leaker was
closed, but self-publishing nodes are a separate vector. Before any GREEN verdict:
- the ON==OFF suite must include **codegen/schedule** assertions, not only `control_in` assertions
  (this blocker is invisible to a chain-only oracle);
- the real-file sweep must cover the OOM giants, not just the tractable subset (the 16-golden subset
  has now hidden a blocker on all four prior passes and the construct subset surfaced StructPromotion
  only because it was deliberately added).

## Cross-references

- `docs/plans/2026-06-04-rebuild-deletion-readiness-audit.md` — pass 1 (postfix bare-expr, resolved).
- `docs/plans/2026-06-04-rebuild-deletion-readiness-audit-rerun.md` — pass 2 (C-`for` my-init, resolved).
- `docs/plans/2026-06-05-rebuild-deletion-readiness-audit-pass3.md` — pass 3 (if/elsif + C-for bare-init, resolved).
- `docs/plans/2026-06-02-control-wiring-trio-comparison.md` — execution log; the `my`-decl postfix leak
  and the StructPromotion divergence should be appended to its remaining-work.
- `docs/plans/2026-06-01-merge-and-control-implementation-plan.md` — Phase 2; the self-publishing
  `my`-decl is the same "node constructed without the enclosing statement seeing its left sibling"
  frontier, now in the postfix-body sub-case.
- Memory: `block_action_workaround_accretion.md`, `phi_merge_strategy.md` — the postfix-body `my`-decl
  is another instance of the mid-statement-node-misses-its-context failure mode.
