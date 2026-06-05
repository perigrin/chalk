# Clean Control-Construction Design (RE-DERIVED)

**Date:** 2026-06-05
**Branch:** phase1-lateral-bindings @ ccee2d05
**Status:** Design document. No lib/ or t/ modifications. Alignment audit (2026-06-05, `2026-06-05-control-construction-alignment-audit.md`) returned GREEN: construction-time `control_in` has zero consumer (no mid-parse reader; all scheduler/optimizer/codegen consumers read the completed graph; GCM builds from the completed CFG). Option X confirmed; this returns to the 2026-06-02 adversarial conclusion, now backed by 5-leaks-in-4-passes. One correction folded in: KEEP the merge-only hygiene loop (graph-membership consumers rely on it). Ready to implement pending perigrin's go.
**Supersedes:** the prior version of this file, whose Part 1 premise (graph-completion merges are load-bearing, therefore a post-pass is required regardless) has been EXPERIMENTALLY FALSIFIED.

**Predecessors:** `docs/plans/2026-06-02-control-wiring-trio-comparison.md`; the four audits `2026-06-04-rebuild-deletion-readiness-audit{,-rerun}.md`, `2026-06-05-rebuild-deletion-readiness-audit-pass3.md`, `-pass4.md`.

---

## Verified Fact Base (all confirmed by in-code experiment)

**FACT 1 — the graph-completion merges are NOT THE REASON a post-pass is needed; but they are NOT safe to delete either (corrected by the alignment audit).** The prior design claimed the Block rebuild's `$graph->merge($s)` calls (Actions.pm:1691, 1729) are required because `_finalize_body_graph` (1016-1138) only reaches nodes transitively from Returns via `inputs()`. The closure ACTUALLY follows BOTH `inputs()` AND `control_in` (line 1130). Experiment (this session): guarded the two merge calls behind `$ENV{CHALK_NO_MERGE}` (guard since reverted — not in tree), ran a gate subset with merges DISABLED (control threading still on): byte-compat 19/19, byte-compat-schedule 19/19, bnf-target-c 178/178, c-schedule-walker / ir-use-def / ir-hash-consing / struct-promotion-end-to-end all 0 failures; the orphan case kept VarDecl($orphan) in `$graph->nodes` via the implicit Return's `control_in` chain.

**BUT the alignment audit (2026-06-05) found this experiment's gate set was too narrow.** Four `$graph->nodes` consumers take membership as given — `Optimizer/DCE.pm:39`, `Perl/Target/Perl.pm:467`, `Perl/Actions.pm:839`, `MOP/Class.pm:142` (+ `IR/Serialize/JSON.pm:97`). Graph completeness via the closure is correct ONLY if the `control_in` chain is perfectly intact for every body; a cheap explicit merge guarantees membership unconditionally. **RESOLUTION: KEEP a merge-only hygiene loop** (correctness over cleanliness). The earlier "lean delete" was wrong. What FACT 1 actually establishes is narrower but still decisive for the X-vs-Y question: graph completion is NOT an INDEPENDENT reason to keep a post-pass *that does control threading* — the merges are a separate, cheap, retainable concern. The prior design's foundational "a control-threading post-pass loop is required regardless because of graph completion" is GONE; the post-pass is justified on control-threading correctness alone (Parts 2-4), and a tiny merge loop rides along.

**FACT 2 — graph completeness DEPENDS on the control_in chain being intact.** The closure reaches a statement node only by walking `control_in` (and `inputs`) back from the Return. So correct control threading is not just the CFG requirement — it is ALSO what makes the graph complete. The two requirements are unified: correct `control_in` is sufficient for both.

**FACT 3 — a leak does not DROP nodes; it produces SPURIOUS/wrong nodes + double-emit.** Blocker #5 (`my $a=1; my $b=foo() if $c; return $a;`): rebuild ON graph = {VarDecl($a), If, Return, Proj×2, Region, Start, Constant×3} with `$b`/`foo()` correctly NESTED inside the If (postfix body), NOT top-level. Rebuild OFF graph = ALSO contains top-level VarDecl($b)+Call (spurious) → the double-emit. A control leak corrupts the graph, it does not merely mis-thread one edge. (Verified this session by dumping `$graph->nodes` ON vs OFF.)

**FACT 4 — the during-parse channel threads flat/simple cases correctly even rebuild-OFF.** `my $orphan=99; bar(); 7;` rebuild-OFF chain = `VarDecl<=Start | Call<=VarDecl | Constant<=Call` (correct). The five blockers are all the leak family: a node self-publishes (or a sub-rule leaks) its control_head via `update_control_head` in a context an enclosing/following construct later reads. postfix (fixed 6cdcb15b), C-for my-init (e5b71467), elsif (f71b4b49), C-for bare-assign init (d7070e25), my-decl-postfix (#5 OPEN), probable StructPromotion (#6).

**CONSTRAINT (governs everything):** the current scheduler (EagerPinning) is a "good enough to work" PLACEHOLDER, slated for re-evaluation (GCM or other). No architectural decision is justified by appeal to its behavior. The durable invariant is "the IR's `control_in` edges are correct," because whatever scheduler replaces EagerPinning reads them as ground truth.

---

## Part 1: The Minimal Post-Parse Pass — revised from the falsified premise

The prior design's argument ("Job B graph-completion needs a post-pass loop regardless; adding Job A control-threading is free") is VOID — Fact 1 falsifies it. Graph completion is delegated to `_finalize_body_graph`'s `control_in`-following closure provided the chain is intact (Fact 2). So whether a post-pass is needed reduces ENTIRELY to the control-threading question.

Two minimal end states:
- **End State A (post-pass SoR):** the Block rebuild iterates `@stmts` in source order and sets `control_in` on every statement node; it is the sole producer of correct `control_in`. The during-parse channel becomes dead (overwritten) and is removed. Graph completion follows from the correct chain.
- **End State B (during-parse SoR):** the rebuild is deleted; the during-parse channel is made leak-free so every node has correct `control_in` at action-fire time. Graph completion follows automatically (Fact 2). No post-pass of any kind.

Both produce the durable invariant. The difference is WHERE/WHEN correctness is established.

---

## Part 1.5: Why Chalk differs from other SoN front-ends (the architecture-specific crux)

Classic Sea-of-Nodes front-ends (HotSpot C2, Click's original) DO build the
graph during parsing — but they parse an already-structured AST/bytecode
TOP-DOWN, with full parent/sibling context available at each node as they
descend. Control's defining relationship — a side-effect node's predecessor is
its LEFT SIBLING statement — is trivially available in a top-down walk.

Chalk is architecturally different (see memory `ir_construction_during_parse_option_a`).
Its semantic-action layer is a PURE SYNTHESIZED-ATTRIBUTE FOLD (Loup Vaillant
Earley model): a rule's action sees ONLY its children's results — there is no
inherited-attribute / left-sibling→right-sibling channel. The one relationship
a synthesized fold structurally cannot hand across is exactly the
left-sibling-predecessor that control needs. The during-parse lateral-seed
channel is an attempt to bolt an inherited channel onto a synthesized fold; the
five-leak family is the symptom of fighting the attribute model. A post-parse
pass operates AFTER the fold completes, when the flat source-ordered `@stmts`
is materialized — so the left-sibling relationship is directly available, with
no fold to fight. This is why "other SoN implementations do during-parse" does
NOT transfer: they aren't building over a synthesized-attribute Earley fold.

So the user's framing — "is it easier / more correct to build control_in during
construction or in a post-parse-pre-schedule pass?" — answers: the post-pass is
BOTH easier (it already exists, ~60 lines, correct-by-construction; adopting it
is net deletion) AND more correct (5 incorrectness bugs in the during-parse
channel vs 0 in the post-pass), *because of* Chalk's synthesized-fold
architecture, not in spite of it.

---

## Part 2: The Real Fork

**Option X — post-parse pass is system of record.** The rebuild iterates the materialized flat `@stmts` list AFTER all actions fire, calling `set_control_in($current_control)` and advancing. It sees every statement once, in source order, no sub-rule ambiguity, no timing dependency, no `update_control_head` side-channel. It is the last writer and always wins. The during-parse channel's values are overwritten — it can be deleted. Correctness condition: the Block action extracts the right `@stmts` (already required for codegen/scheduling regardless; no known failure mode).

**Option Y — during-parse channel is system of record.** The channel (Earley lateral-seed Cases 1/2; StatementItem publisher; `one_with_control`) delivers the predecessor as the seed; actions consume `$ctx->control_head` to set `control_in` at construction. Correctness condition: every publisher fires where no enclosing/same-statement node has clobbered the visible control_head. This has sprung FIVE leaks across FOUR audits. Under Y, leak-freedom is a CORRECTNESS requirement (Fact 3: leaks corrupt the graph), not a nicety.

**Evaluation (scheduler-independent):**
- X's condition (`@stmts` correct) is an existing, never-failing invariant; the re-threading is an exhaustive O(n) iteration no construct escapes.
- Y's condition has failed in 5 distinct constructs. Root cause: `update_control_head` is a shared mutable slot (`SemanticAction.pm:39`) conflating "advance the sibling chain" (correct) with "I am a sub-expression whose value is a control-interesting node" (leaks). The action cannot tell at fire-time whether it is at a statement boundary; the grammar nesting context is not visible inside the action method.

---

## Part 3: Does Fact 3 decisively favor X? — Yes

Fact 3 makes the stakes asymmetric: under Y a leak is graph corruption (duplicate nodes, broken codegen); under X a during-parse leak is harmless (overwritten). 

Can Y be made leak-free by construction? The publishers split into: (1) correct statement-boundary publishers (not the problem); (2) structural suppressors that publish Start — Block (1766), ElsifChain (2891 after f71b4b49) — safe; (3) self-publishing mid-statement nodes — VariableDeclaration (1900), AssignmentExpression init-fold (2441) — the live leak vectors. Fixing (3) structurally needs the action to know it is NOT at a top statement boundary, which is not cheaply available at fire-time. The only mechanism available given the current action API is the `_find_pre_init_control_head` tree-walk (134-149) — a per-construct bespoke fix, already applied at C-for (e5b71467) and bare-init (d7070e25); blocker #5 would need a second call site in PostfixModifier; #6 likely a third. That is the whack-a-mole. X sidesteps it entirely: the post-pass ignores whatever the channel published.

**Verdict: a leak-proof during-parse channel is not achievable without either redesigning the `update_control_head` API to carry statement-boundary metadata (deeper than either option) or continuing whack-a-mole. Fact 3 decisively favors X.**

---

## Part 4: Recommendation — Option X, retire the channel

**The post-parse rebuild is the system of record for control threading. The during-parse lateral-seed channel is retired in full.** Reasons (all scheduler-independent): (1) the post-pass re-threads `control_in` unconditionally from the materialized `@stmts` — no construct escapes; (2) Y's leak-freedom is not achievable without per-construct bespoke fixes, 5 leaks and counting; (3) Fact 3 makes X degrade gracefully and Y degrade into graph corruption; (4) the post-pass is correct by construction over source order, O(n), no timing deps; (5) `Node.pm:26-28` already documents the post-pass as the architecture — the channel was an addition.

**Blocker #5 (`my $x=E if C`): NOT worth fixing as a channel fix.** Under X, PostfixModifier reads the self-published VarDecl as predecessor (wrong), but the post-pass's If/Loop branch (1744-1748) rewrites `inputs[0]` to the correct chain tail. Final IR correct; channel incorrectness overwritten. Fixing #5 builds infrastructure for a mechanism being deleted.

**Blocker #6 (StructPromotion.pm): NOT worth fixing as a channel fix** — same overwrite argument. It is additionally entangled with a pre-existing VarDecl write-shape bug (Actions.pm:767 uses the old 3-input `[control,name,init]` shape post-Proposal-2); that bug is a Proposal-2 follow-up to fix regardless, orthogonal to control threading, tracked separately.

---

## Part 5: Concrete End-State Spec

**Delete — Actions.pm:** toggle API (91-94); `$do_rewrite` gate (1684) + the four `if ($do_rewrite ...)` wrappers (keep bodies); `_thread_control_head` (119-124) + call sites (385, 405, 1227); `_find_pre_init_control_head` (134-149) + call site (3214); ForStatement during-parse fix block (3195-3230); all chain-advancing `update_control_head` calls in actions (StatementItem 388/419, PostfixModifier 2565/2629, IfStatement 2794, ElsifChain 2891, WhileStatement 3028, ForStatement 3186, ForeachStatement 3371); VariableDeclaration self-publish (1900); AssignmentExpression init-fold publish (2441); Block outward suppressor (1766, after confirming no action reads control_head for threading).

**Delete — Earley.pm:** lateral-seed Cases 1/2 + `$lateral_seed` (718-737); `_predict` `$control_head` param + `$seed_value` conditional (1235, 1250-1252) → always `one()`.

**Delete — SemanticAction.pm:** `one_with_control` + `%_one_with_control_cache` (205-219, 226); `$_pending_control_head_update` (39); `update_control_head` (257-263); `_complete_sa` application block (411-429).

**Keep — Actions.pm:** the rebuild loop body 1685-1752 (becomes unconditional); `set_control_in`/region-advance logic (this IS Job A); `update_scope`/`update_graph`/`update_annotations`; `_finalize_body_graph`.

**Merges (1678/1691/1729) — DECIDED: KEEP a merge-only hygiene loop.** The alignment audit (2026-06-05) resolved this: four `$graph->nodes` consumers (DCE.pm:39, Target/Perl.pm:467, Actions.pm:839, MOP/Class.pm:142) take membership as given, and the merge experiment's gate set was too narrow to license deletion. Keep the merges as a cheap unconditional guarantee of graph membership; do NOT make completeness depend on the `control_in` closure being perfect for every body. So the post-pass becomes: an unconditional source-order loop that (Job A) threads `control_in` and (Job B-residual) merges each statement node — Job B kept not because it's load-bearing for the X-vs-Y decision but because it's cheap insurance the `$graph->nodes` consumers rely on.

**Rewrite — t/bootstrap/control-threading.t:** remove all `disable/enable_control_rebuild` pairs; rewrite every `chain_for($src,0)` vs `chain_for($src,1)` differential-oracle assertion as a fixed golden (expected = current rebuild-ON output). Add codegen/SCHEDULE-level assertions (not chain-only — Fact 3 shows chain-only oracles miss the double-emit) for: my-decl-postfix all flavors (#5 — confirm the post-pass corrects it), TryCatch, nested-loop, loop-then-if, postfix-after-control-flow, postfix-chain.

---

## Part 6: Migration Order

- **Phase 1 — delete toggle, rebuild unconditional.** Remove toggle API + `$do_rewrite` gate (keep bodies). Rewrite control-threading.t differential blocks to fixed goldens. Gates: bnf-target-c 178/178 x2, byte-compat 19/19, byte-compat-schedule 19/19, leo 4/4.
- **Phase 2 — delete the Earley channel.** Remove Cases 1/2, `_predict` param, `one_with_control`. Add control-threading.t codegen/schedule assertions for #5-shape + gap shapes. Gates: same + full suite failure set == baseline (54).
- **Phase 3 — remove action `update_control_head` publishers** + `_thread_control_head` + `_find_pre_init_control_head` + ForStatement fix block + Block suppressor. Gates: same.
- **Phase 4 — clean up SemanticAction** (`$_pending_control_head_update`, `update_control_head`, `_complete_sa` block).
- **Phase 5 — real-file sweep** (31 self-hosting files, 0 regressions); resolve the merge decision (Part 5); fix StructPromotion.pm:767 write-shape bug (orthogonal); optionally simplify residual `$ctx->control_head` reads (now always Start).

---

## Part 7: Determinism

Post-pass iterates source-ordered `@stmts`; `$current_control` advances left-to-right → deterministic. `set_control_in` mutates existing nodes (no factory `make`), so no content-hash/identity effect. VarDecl per-position counter ids (Proposal-2 d01bfea3) keep identical decls distinct. After channel retirement, `control_head` is always Start; not in any content hash → no hash-cons instability. Goldens already byte-identical ON==OFF (pass-4 16/16, 44/45 synthetic); making the rebuild unconditional reproduces ON output exactly → no re-baselining.

---

## Part 8: The GCM-Forward Question (for the alignment audit, not to decide now)

Option X hands a future GCM scheduler correct `control_in` by construction — a correct CFG with correct predecessor edges, which is GCM's starting requirement (Click/Paleczny 1995 builds the dominator tree from the COMPLETED graph, not incrementally — suggesting "correct at schedule time" suffices, which X provides). The open question: would a future GCM design specifically need correct `control_in` AT PARSE/construction time (favoring Y)? If so, the response is NOT to resurrect the leaky channel but to design a structurally leak-free two-pass construction then, against concrete requirements. The alignment audit should pressure-test "correct-by-construction-at-schedule-time is sufficient" against plausible GCM designs — NOT against EagerPinning.

---

## Source paths
- `lib/Chalk/Bootstrap/Perl/Actions.pm` (91-94, 119-149, 385, 405, 419, 1227, 1678, 1684, 1691, 1693-1696, 1710-1712, 1729, 1730-1732, 1744-1748, 1766, 1900, 2441, 2565, 2629, 2794, 2891, 3028, 3186, 3195-3230, 3371)
- `lib/Chalk/Bootstrap/Earley.pm` (718-737, 1235, 1250-1252)
- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` (39, 205-219, 226, 257-263, 411-429)
- `t/bootstrap/control-threading.t` (all toggle pairs + differential assertions)
- `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm` (767 — Proposal-2 write-shape follow-up, orthogonal)
- `lib/Chalk/IR/Node.pm` (26-28, doc already matches; no change)
