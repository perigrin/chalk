# Clean Control-Construction Design: System of Record for Threading and Graph Completion

**Date:** 2026-06-05
**Branch:** phase1-lateral-bindings @ f2f8d836
**Status:** Design document. No `lib/` or `t/` modifications. Drives an alignment audit before implementation.

**Predecessor plans:**
- `docs/plans/2026-06-02-control-wiring-trio-comparison.md` — execution log, lateral-seed capstone
- `docs/plans/2026-06-04-rebuild-deletion-readiness-audit.md` — pass 1 (postfix)
- `docs/plans/2026-06-04-rebuild-deletion-readiness-audit-rerun.md` — pass 2 (C-for my-init)
- `docs/plans/2026-06-05-rebuild-deletion-readiness-audit-pass3.md` — pass 3 (if/elsif + C-for bare-init)
- `docs/plans/2026-06-05-rebuild-deletion-readiness-audit-pass4.md` — pass 4 (my-decl postfix; merge load-bearing confirmed)

## Executive Summary

Four audits, five blockers, one family: a node self-publishing or a sub-rule
leaking its `control_head`, so an enclosing or following construct reads the
wrong control predecessor. Four incremental Earley/action fixes (6cdcb15b,
e5b71467, f71b4b49, d7070e25) each addressed one instance. Blocker #5
(my-decl-with-postfix `my $x = E if C`) is open; a probable #6 sits in
`StructPromotion.pm`.

**Recommendation:** The post-parse pass (the Block control-chain "rebuild") is
the **system of record** for control threading. The during-parse lateral-seed
channel is **retired in full**. Blockers #5/#6 are **not worth fixing** as
during-parse channel fixes.

**Why (scheduler-independent):** the post-pass is the one mechanism that
produces correct `control_in` edges *by construction* — it walks the
materialized statement list in source order, with no timing or sub-rule-
visibility dependencies, so no construct can escape it. The during-parse
channel is elegant but has sprung five leaks and is accreting bespoke per-
construct mechanisms; it is not cheaply leak-free. A future scheduler (GCM or
otherwise) will read `control_in` as ground truth, so the durable requirement
is "the IR's control edges are correct," and the post-pass guarantees that
where the channel does not.

## Scheduler caveat (governs this whole document)

The current scheduler (`Chalk::IR::Scheduler::EagerPinning`) is explicitly a
"good enough to work" placeholder, NOT the final architecture. It will be
re-evaluated for GCM or other scheduler options. Therefore this design does
NOT justify any decision by appeal to current scheduler behavior. In
particular, the earlier (trio-comparison) argument "the during-parse leaks
don't matter because the byte-compat-era scheduler is forced to reproduce
source order" is REJECTED here as scheduler-dependent reasoning. The durable
invariant is: **`control_in` edges in the IR must be correct by construction**,
because whatever scheduler replaces EagerPinning will consume them as the
authoritative control-flow predecessor relation. The choice between during-
parse and post-parse is decided by *which mechanism reliably produces correct
edges*, not by what today's scheduler tolerates.

## Part 1: The Two Jobs of the Rebuild, Separated

The Block control-chain rebuild (`Actions.pm:1669–1752`) does two distinct
things, currently interleaved.

### Job A — Control Threading
Each statement-position IR node's `control_in` is set to its source-order
predecessor. The rebuild iterates `@stmts` in order, advancing
`$current_control`: VarDecl (1688–1698), Return/Unwind (1699–1715, no
advance), Call/Assign/CompoundAssign/RegexSubst/TryCatch (1716–1735), If/Loop
(1736–1751, rewire `inputs[0]`, advance to `region // $s`). Gated by
`$do_rewrite = $_control_rebuild_enabled` (1684).

**Correct by construction:** operates on `@stmts`, a flat source-order list.
No timing dependencies, no sub-parse visibility, no `update_control_head`
side-channel. Same source → same `@stmts` → same edges.

### Job B — Graph Completion
Three UNCONDITIONAL merges put every statement-position node into
`$graph->nodes`: `merge($start)` (1678), `merge($s)` for VarDecl (1691),
`merge($s)` for Call/Assign/etc. (1729).

**Load-bearing (verified, pass 4 Dim 4):** `_finalize_body_graph`
(`Actions.pm:1016`) transitively seeds the graph only from Return roots via
`inputs()`. The during-parse chain uses the hash-EXCLUDED `control_in` field
(not `inputs()`), so a top-level side-effect node not otherwise referenced is
in `$graph->nodes` ONLY because of the rebuild's explicit merge. Probe:
`my $x=1; foo(); $x=2; return $x;` → the first VarDecl is in the 10-node graph
but unreachable from the Return via `inputs()+control_in`; it is present solely
via line 1691. Wholesale deletion would drop it.

**Conclusion:** a post-parse loop calling `$graph->merge($s)` per statement-
position node is UNCONDITIONALLY REQUIRED and cannot be subsumed by
`_finalize_body_graph`. Once that loop must exist, adding source-order control
threading (Job A) to it costs nothing.

## Part 2: The Leak Family Root

`update_control_head` is a process-wide mutable slot
(`SemanticAction.pm:39`) shared across a rule completion's during-parse extent.
`_complete_sa` stamps it onto the result Context's `control_head`; `_mul_ctx`
(150–165) propagates it upward (right wins unless left non-Start and right
Start). It is called with three indistinguishable intentions:

1. **(correct)** "I am a top-level statement; here is my node for the next
   sibling." — IfStatement Region (2794), WhileStatement Region (3028),
   Call/Assign via StatementItem (419).
2. **(leaked)** "I am a sub-rule; here is my Region." — ElsifChain (was 2881),
   read by the enclosing IfStatement as the outer If's predecessor.
3. **(leaked)** "I am a same-statement body node; here I am." —
   VariableDeclaration self-publishing (1900) when `my $b = foo()` fires before
   the same-statement PostfixModifier reads it.

| Blocker | Root | Fix | Approach |
|---|---|---|---|
| postfix modifier | seed not delivered into sub-rule | 6cdcb15b | Earley prediction-point seed (bespoke) |
| C-for my-init | Intention 3 | e5b71467 | `_find_pre_init_control_head` tree-walk (bespoke) |
| if/elsif outer-If | Intention 2 | f71b4b49 | publish Start (symptom suppressor) |
| C-for bare-assign init | Intention 3 | d7070e25 | extend e5b71467 |
| my-decl postfix (OPEN) | Intention 3 | — | would need generalized tree-walk in PostfixModifier |

f71b4b49 closed the last *sub-rule* (Intention 2) leaker. Intention 3
(self-publishing nodes in sub-positions) is a SEPARATE vector and is not
closed: any node type that self-publishes and can appear as a postfix body /
for-init / nested position is a new blocker. The publisher fires BEFORE the
enclosing rule, so no sub-rule-boundary suppressor can prevent it; each
enclosing construct needs its own "recover the pre-publication predecessor"
mechanism — i.e. the `_find_pre_init_control_head` pattern, applied per
construct. That is the accretion.

## Part 3: Recommendation — Post-Parse Pass as System of Record

**The post-parse pass is the system of record for control threading; the
during-parse lateral-seed channel is retired in full.**

Arguments (all scheduler-independent):
1. Job B requires an unconditional post-pass merge loop regardless (Part 1).
   Adding Job A to it is free.
2. The post-pass is correct by construction over source order; no construct
   escapes it.
3. The during-parse channel is not cheaply leak-free (Part 2); fixing each
   blocker reproduces, one construct at a time, what the post-pass already does
   uniformly.
4. Four fixes across four audits, one blocker still open, a sixth likely.
5. This is NOT trio-comparison "Proposal 3" (move threading into the
   scheduler — "heavier"). It KEEPS the rebuild loop where it lives, deletes
   the toggle (always-on), and retires the channel that was meant to replace
   it. Net simpler than the current dual-mechanism state.
6. `Node.pm:26–28` already documents this as the architecture
   ("set by the Block control-chain fixup pass via `set_control_in()`"); the
   channel was an addition.

**Durable-invariant framing (replacing the rejected scheduler-tolerance
argument):** a future GCM/other scheduler reads `control_in` as the
authoritative control predecessor relation. The requirement is therefore
"`control_in` is correct by construction." The post-pass guarantees this; the
leaky channel does not. This is exactly why the post-pass should be the system
of record — and exactly why the channel's residual leaks are not a reason to
keep extending it.

### Trade-off acknowledged (and explicitly deferred to the scheduler re-eval)
A leak-free during-parse channel would set correct `control_in` at construction
time, which a GCM scheduler *might* exploit for earlier scheduling freedom.
Whether that matters is a question for the scheduler re-evaluation, with
concrete GCM requirements in hand — NOT something to pre-build a leak-prone
channel for now. If that re-eval shows during-parse control accuracy is needed,
the mechanism can be designed then against real requirements (and may not be
the current lateral-seed channel at all — e.g. SSA construction from the
materialized graph). Until then, the post-pass is the system of record and the
IR it produces is correct, which is all any future scheduler needs as a
starting point.

## Part 4: Consequence for Blockers #5 and #6

**Not worth fixing as during-parse channel fixes.** Under this design, blocker
#5 manifests as: PostfixModifier reads `control_head` (a wrong, self-published
VarDecl), builds the If/Loop with the wrong predecessor, and the post-pass
overwrites the If/Loop's `inputs[0]` with the correct chain tail. Final IR is
correct. Same for #6 (StructPromotion.pm). The channel's residual incorrectness
at construction is overwritten by the authoritative post-pass, so the IR the
future scheduler sees is correct regardless. Fixing #5/#6 in the channel builds
infrastructure for a mechanism being deleted.

(If the team ever chose during-parse as SoR — rejected here — #5 would need a
generalized `_find_pre_init_control_head` call in PostfixModifier. This design
recommends against that road.)

## Part 5: Concrete End-State Spec

### Delete — `Actions.pm`
- Toggle API (91–94): `$_control_rebuild_enabled`, `disable_control_rebuild`,
  `enable_control_rebuild`, `control_rebuild_enabled`.
- `_thread_control_head` helper (119–124) + call sites (StatementItem 405,
  TryCatch 1227).
- `_find_pre_init_control_head` helper (134–149).
- ForStatement during-parse fix block (3195–3230).
- `$do_rewrite` gate (1684) and the four `if ($do_rewrite ...)` wrappers
  (1693, 1710, 1730, 1745) — keep the bodies (now unconditional).
- All chain-advancing `update_control_head` calls in actions: StatementItem
  (388, 419), VariableDeclaration (1900), AssignmentExpression init-fold
  (2441), PostfixModifier (2565, 2629), IfStatement (2794), ElsifChain (2891),
  WhileStatement (3028), ForStatement (3186), ForeachStatement (3371).
- Block's outward suppressor `update_control_head($start)` (1766) — no-op once
  no action body publishes; delete in Phase 3.

### Keep — `Actions.pm`
- `merge($start)` (1678), `merge($s)` (1691, 1729) — load-bearing.
- All `set_control_in` / region-advance logic in the rebuild loop body.
- `update_scope` / `update_graph` / `update_annotations` in actions.
- `_finalize_body_graph` (1016–1138).
- `$ctx->control_head` reads in actions (read Start after retirement;
  harmless; a later cleanup can simplify to `$factory->make('Start')`).

### Delete — `Earley.pm`
- Lateral-seed Cases 1 & 2 + `$lateral_seed` (718–737).
- `_predict` `$control_head` parameter and `$seed_value` conditional (1235,
  1246–1252) — always `$semiring->one()`.

### Delete — `SemanticAction.pm`
- `one_with_control` + `%_one_with_control_cache` (205–219) and its
  `reset_cache` line (226).
- `$_pending_control_head_update` (35–39), `update_control_head` (257–263),
  and its `_complete_sa` application block (411–430) — Phase 4.

### Rewrite — `t/bootstrap/control-threading.t`
Remove all `disable/enable_control_rebuild` calls. Rewrite every
`chain_for($src,0)` vs `chain_for($src,1)` differential-oracle assertion as a
fixed golden assertion (expected = post-pass output = current rebuild-ON =
current goldens). Add codegen/schedule-level assertions for my-decl postfix
(blocker #5 — must emit correctly under the unconditional post-pass),
TryCatch, nested-loop, loop-then-if.

## Part 6: Migration Order
- **Phase 1 — retire the Earley channel** (Earley `_predict` + Cases 1/2;
  delete `one_with_control`). Rebuild still ON, corrects everything. Gates:
  leo 4/4, bnf-target-c 178/178 x2, byte-compat 19/19 + schedule 19/19.
- **Phase 2 — delete the toggle, rebuild unconditional** (remove
  `$do_rewrite`). Rewrite control-threading.t to fixed goldens. Gates: + full
  suite failure set == baseline (54).
- **Phase 3 — remove action `update_control_head` publishers** + delete
  `_thread_control_head`, `_find_pre_init_control_head`, ForStatement fix
  block, Block suppressor. Gates: + new codegen/schedule assertions.
- **Phase 4 — clean up SemanticAction** (`$_pending_control_head_update`,
  `update_control_head`, `_complete_sa` block).
- **Phase 5 — real-file sweep** (parseable lib/*.pm, 0 regressions) +
  StructPromotion.pm:767 old-VarDecl-shape bug (orthogonal, tracked).

## Part 7: Determinism
Post-pass operates on source-ordered `@stmts`; `$current_control` advances
left-to-right → deterministic `control_in`. Merges keyed by `content_hash()`
(VarDecl = per-position counter id, advancing in grammar/source order).
After retirement, `control_head` in multiply-Contexts is always Start; not part
of `content_hash`, so no hash-cons instability. Goldens are already byte-
identical ON==OFF (pass 4: 16/16); making the rebuild unconditional reproduces
ON output exactly — no re-baselining. Leo equivalence is parse-time,
independent of threading.

## Part 8: Open question the alignment audit must answer
Is this recommendation sound GIVEN the scheduler is a placeholder slated for
re-evaluation? Specifically: does making the post-pass the authoritative
producer of `control_in` (correct-by-construction IR) leave a future GCM
scheduler everything it needs, OR is there a concrete GCM requirement that
demands correct `control_in` *at parse time* (which only a leak-free during-
parse channel could give)? If the latter, the recommendation flips and #5/#6
matter. The audit should pressure-test the durable-invariant claim against
plausible GCM designs rather than against the current EagerPinning behavior.

## Cross-References
- Trio comparison "step-3 fork": resolved as neither "during-parse capstone"
  nor "complete the scheduler" — keep the post-pass, retire the channel.
- `block_action_workaround_accretion.md`: the four lateral-seed fixes ARE the
  accretion that note warned about; this design retires them.
- `ir_construction_during_parse_option_a.md`: revises "during-parse achievable"
  — achievable for constructs tested then, NOT structurally leak-free for the
  self-publishing-node family (Intention 3).

**Source paths:** `lib/Chalk/Bootstrap/Perl/Actions.pm` (91–94, 119–149, 388,
405, 419, 1227, 1669–1752, 1766, 1900, 2441, 2565, 2629, 2794, 2891, 3028,
3186, 3195–3230, 3371); `lib/Chalk/Bootstrap/Earley.pm` (699–737, 1235–1252);
`lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` (35–39, 205–219, 257–263,
411–430); `t/bootstrap/control-threading.t`; `lib/Chalk/IR/Node.pm` (26–28);
`lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm` (767).
