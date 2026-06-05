# Validation: Move IR Construction Wholly Post-Parse (eliminate SemanticAction-as-builder)

**Date:** 2026-06-05
**Branch:** phase1-lateral-bindings @ 8a5581ee
**Status:** Validation + design. No lib/ or t/ modifications. Pressure-tests the disease-level fix proposed by perigrin and pointed at by the 2026-05-31 architecture review's Next Questions (lines 246-247). Verdict drives whether Option X is a standalone fix or Phase 1 of a larger vision.

**Anchors:**
- `paad/architecture-reviews/2026-05-31-chalk-semantic-action-architecture-report.md` — root finding F1 (SemanticAction is a forced fit in the semiring), and F2/F3/F4/F5/F13 as symptoms of that placement.
- `docs/plans/2026-06-05-clean-control-construction-design.md` + `-control-construction-alignment-audit.md` — the Option X decision (post-pass control threading, GREEN).

## The proposal

Eliminate SemanticAction as an effectful in-parse IR builder. Instead: the Earley parse produces a disambiguated Context tree (the four PURE filter semirings stay); a SEPARATE post-parse pass folds that tree into the SoN IR graph AND the MOP metadata, with full parent/sibling/child context available. This kills the root cause (F1) and its symptoms (F2 mailbox, F3 Context hub, F4 Block rebuild, F5 control smear, F13 cfg_state) rather than relocating them. Option X (post-pass control threading only) is the narrowest slice.

## Decisive question — VERDICT: VIABLE (no constraint)

**Does any parse-time disambiguation depend on CONSTRUCTED IR, or only on annotation tags?** Answer: only tags + token text + parser state. Independently re-verified against current code (not just the review):

- **The 4 filter semirings touch ZERO constructed IR.** grep for `->graph|->factory|->mop|->control_in|Chalk::IR::Node|NodeFactory|->operation|->inputs` across Boolean/Precedence/TypeInference/Structural = 0 hits each. They read `annotations()->{own-slot}`, `focus()` (token), `children()` (Context).
- **No action method can reject a parse.** grep for `is_zero|->zero|set_zero` in Actions.pm (3405 lines) = 0. Every zero-return in SemanticAction.pm is pure propagation (`if $X->is_zero`), never origination. So construction cannot change parse acceptance.
- **FilterComposite decides before SA runs and excludes SA from compare.** `multiply` runs the 4 filters first, rejects on any `is_zero`, then threads TI's tag hash one-way into SA, then runs SA (whose only feedback is propagated zero). `_filter_compare` iterates "all semirings except the last (SA)".
- **The only Earley IR-read is the lateral-seed channel** (Earley.pm:721-733) — reads `control_head->operation` purely to pick `_predict`'s seed value (`one_with_control` vs `one`). That is construction-seeding (the channel Option X deletes), NOT disambiguation steering. It selects no DFA item, gates no scan, feeds no verdict.

**Conclusion:** if SemanticAction built no IR during the parse, the four filters would produce byte-identical disambiguation. The disambiguation half and the construction half are already cleanly separated (review S1, code-confirmed). IR construction can move wholly post-parse.

## Post-pass input — already retained

The disambiguated parse output is the winning derivation's full Context tree, retained intact: `parse_value` returns the final `$result` Context; `Context.children` is a `:reader` param (ordered arrayref, not pruned). `FilterComposite::_wrap_sa_result` merges all four filters' slot results (incl. TI's `type` tag hash) into EVERY result Context's annotations. So every node carries (focus token, rule, annotations{boolean,precedence,type,structural}, children) — everything the actions consume. The single TI→action cross-coupling (`Actions.pm:899` MethodDefinition reading `method_return_type`) is an annotation tag, present on the tree. A post-pass walks this tree (any order — full context) and builds both the SoN IR and the MOP metadata. Only each node's `focus` changes (raw structural value instead of SA-built IR node).

This is exactly the materialized-flat-tree the clean-control-construction design's Part 1.5 identifies: the left-sibling-predecessor relationship control needs (which the synthesized-attribute fold structurally cannot hand across — root of F4/F5 and the 5-leak family) is directly available in a post-pass.

## Scope / effort / risk

- **Moves to the post-pass:** ~64 action methods in Actions.pm; 97 `->make()` calls; 55 graph touches; MOP Info construction. Big movers: Program/StatementList/Block/_finalize_body_graph; ClassBlock/MethodDefinition/SubroutineDefinition; VariableDeclaration/AssignmentExpression/CallExpression/BinaryExpression/If/While/For/Foreach/TryCatch.
- **Stays during-parse:** the 4 filter semirings + FilterComposite disambiguation (~2,100 lines, unchanged). Parse produces the annotated Context tree and stops.
- **Deleted by the full vision:** mailbox statics (F2: 5 lexicals + ~74 call sites); Block rebuild god-method (F4, ~158 lines); control-threading smear (F5: 11 fallback sites + lateral-seed + one_with_control + update_control_head); cfg_state/@_cfg_struct_keys (F13); SA-as-semiring special-casing in FilterComposite (F1: _wrap_sa_result, TI→SA threading, SA-skip, _sa path); Context payload fields graph/bindings/factory/control_head/mop (shrinks F3's 14-field hub); dead _transferred_scope (F6), dead error field (F8).
- **Determinism/byte-compat:** plausible and arguably safer — the post-pass has MORE context than the fold. Hazards: deterministic Context-tree iteration order (children are ordered → fixed walk available); identical content-based node ids (same tokens → same hash-cons keys); goldens ARE current output (post-pass must reproduce exactly — feasible from same disambiguated structure).
- **Risk:** a multi-thousand-line relocation of the most load-bearing, LEAST unit-tested code (F16: the Block rebuild has no isolated unit spec — exercised only end-to-end). The danger is migration SAFETY, not architecture (the separation is clean).

## Migration strategy — strangler-fig, incremental, NOT big-bang

The strangler path exists precisely BECAUSE disambiguation never reads IR: during-parse construction can keep running as an oracle while the post-pass is validated family-by-family, then deleted.

1. **Phase 1 = Option X** (specced, GREEN, net-deletion): post-pass owns control threading only; delete the during-parse control channel. Validates the post-pass approach on the narrowest correctness-critical slice.
2. **Build the F16 unit harness** — direct Context→IR/MOP post-pass specs independent of goldens. PREREQUISITE for Phase 2+; without it the rewrite rides only on end-to-end goldens (the 80-90%-drift pattern CLAUDE.md warns against).
3. **Move construction family-by-family** behind golden + unit gates: control constructs → MOP builders → expression/node builders. Keep during-parse construction as a cross-check oracle until each family flips.
4. **Final cleanup:** drop Context payload fields, delete the mailbox, collapse FilterComposite's SA special-casing.
5. Carry forward Option X's KEEP-merge-hygiene decision: the full post-pass must guarantee `$graph->nodes` membership explicitly (4 consumers: DCE.pm:39, Target/Perl.pm:467, Actions.pm:839, MOP/Class.pm:142), not depend on a perfect control_in closure.

## Option X as Phase 1 — CONFIRMED

Option X is a strict sub-slice and composes with the full vision (no rework): it establishes the post-pass-over-materialized-`@stmts` as system of record for control_in and deletes the during-parse channel — the same direction and same deletions the full vision needs. Its specific edits (delete toggle, unconditional rebuild, retire channel, rewrite control-threading.t differentials to fixed goldens) are all steps the full vision needs anyway.

## Recommendation

**Pursue the full vision incrementally, Option X as Phase 1, but gate Phase 2+ on building the F16 unit harness first.** The architecture is genuinely viable — an adversarial search for a hidden dependency that forces a big-bang or breaks disambiguation found none. The bar for "viable" is met; the bar for "big-bang now" is not, solely because the load-bearing construction code lacks isolated unit coverage. Stopping at Option X removes one symptom and leaves the disease (IR-in-semiring); the full vision is the disease-level fix and is reachable without ever going red, provided the unit harness lands before Phase 2.

## Independent verification (this session)
- Actions.pm rejection-origination: `grep -c is_zero|zero|set_zero` = 0. CONFIRMED no action rejects.
- 4 filter semirings IR-touches: 0 each. CONFIRMED.
- Earley IR-reads: only the lateral-seed channel (721-733), construction-seeding not disambiguation. CONFIRMED.
