# Plan Review — Target-Layer Reconciliation Plan

**Date:** 2026-06-09
**Reviews:** `docs/plans/2026-06-08-ir-taxonomy-reconciliation.md` (revised to fold in
the architecture review)
**Reviewer:** project-plan-reviewer agent + verification against the actual code.
**Verdict:** NOT ready to execute as written. 5 Critical, 8 Important, 4 Minor holes.
The plan's *direction* is sound (confirmed by the prior architecture review); its
*sequencing, decomposition, and several specifications* have load-bearing errors.

## Critical (must fix before execution) — all verified against code

### C1. "Corpus stays GREEN at every step" CONTRADICTS Phase G's purpose
Phase G (G.1 MISCOMPILE reclassification, G.2 libperl-free guard, G.3 TypedInvariant)
EXISTS to make the gate fail things it currently passes. A case passing as GAP under
the lax gate becomes MISCOMPILE; a GREEN with an undetected libperl symbol (classes.t
has NO libperl assertion today — F4) becomes FAIL. The plan's whole-refactor invariant
"the corpus MUST stay GREEN at every step" is therefore WRONG for Phase G.
**Fix:** state explicitly that after Phase G the GREEN set may legitimately SHRINK;
any case Phase G newly-fails is a real latent bug Phase G EXPOSED (fix it or correct
the corpus), not a regression. The "stays GREEN" invariant applies to the
node-convergence phases (0–6), NOT to Phase G.

### C2. F8 does NOT "dissolve in Phase 1+" — verified
`And`/`Or`/`Not` are CANONICAL `%DATA_CLASSES` nodes (NodeFactory.pm:109,111) — they
are NOT deleted by any convergence phase, and no phase touches `_lower_and`/`_lower_or`
(which hardcode `icmp ne i64`, LLVM.pm:1515,1668). So F8 (inline hardcoded-i64
truthiness, §2 violation, latent Bool/Num miscompile) does NOT dissolve.
**Fix:** F8 must be EXPLICITLY fixed in Phase G (G.7), not deferred-as-dissolving. AND:
routing `_lower_and` through an explicit `Coerce(*→Bool)` node would require ADDING
Coerce input-edges to the L1/L2 logical.md ir-blocks (they don't have them) — changing
the corpus shape. So G.7's two options are NOT equivalent: "route through Coerce" =
corpus rewrite; "loud die on non-Int operand" = no corpus change. The plan must PICK
one. Recommended: loud-die now (keeps L1/L2 green, removes the silent miscompile);
defer the route-through-Coerce purity to a tracked follow-up.

### C3. Phase 4 ↔ Phase 5 are entangled — "independently revertible" FAILS
`Call.target` is a `Chalk::MOP::Method` (Call.pm:23,35). Phase 4 ("lower
`Call(dispatch_kind='method')` resolving the callee from `Call.target` (MOP::Method)")
needs the MOP structure that Phase 5 introduces. All 7 classes.md ir-blocks interleave
ClassDecl + MethodCall + New + MethodDef (29 refs), so Phase 4 and Phase 5 rewrite the
SAME blocks. Phase 4 cannot produce a committable GREEN corpus without Phase 5's MOP
structure already present.
**Fix:** merge Phase 4 + Phase 5 into one phase (MOP structure FIRST, then dispatch
onto it), OR re-order so Phase 5 (MOP/ClassInfo) precedes Phase 4 (Call dispatch).
The "each phase independently revertible" safety claim must be corrected — these two
land together.

### C4. Phase 5 is a hidden mega-task, not bite-sized
Phase 5.1 is ONE sub-step that simultaneously: defines the `%ref`-input mechanism for
MOP objects in `build_graph_from_ir`, rewrites ALL 7 classes.md ir-blocks at once
(ClassDecl is in every case — can't half-remove from one), AND rebuilds the entire G5
object-model lowering (per-class vtable + object struct + ADJUST order) from the MOP
layer — discarding the G5-campaign LLVM arms in one commit while keeping 7 cases green.
**Fix:** decompose: 5.1 establish ClassInfo consumption in LLVM + the `%ref` harness
syntax WITHOUT deleting any parallel arms; 5.2 ClassDecl→ClassInfo; 5.3
MethodDef→MethodInfo; 5.4 FieldDef→MOP::Field; 5.5 AdjustBlock→MOP::Phaser::Adjust.
Each keeps the corpus green independently.

### C5. G.3 (extend TypedInvariant) chicken-and-egg
G.3 (Phase G, before convergence) would add `%OP_REQUIRED_REPR` checks for the G3–G5
ops. But those are the PARALLEL ops (ArrayRead/MethodCall/...) being DELETED in Phases
1–4 — the checks + their bilateral `well-typed-graph.t` cases become dead code on the
first convergence commit. Writing them against CANONICAL ops instead requires knowing
the final repr-dispatch shape, which only exists AFTER Phases 1–4.
**Fix:** move G.3 OUT of the monolithic Phase G and make it PER-PHASE: each node phase
extends TypedInvariant for the canonical op it lands (Phase 1 → Subscript/PostfixDeref
operand reps; Phase 4/5 → Call-method invocant=Object; etc.), with bilateral coverage
at that phase. Phase G keeps only the gate-mechanism fixes (G.1/G.2/G.5/G.6) that are
independent of the final op set. (G.7/F8 stays in Phase G as a loud-die fix.)

## Important (specify before/at execution)

- **I1.** The `Assign(Subscript-lvalue, val)` ir-block SYNTAX is unspecified; Phase 3
  blocks on it. `build_graph_from_ir` (`MdtestCorpus.pm` _build_node_from_rhs) has no
  lvalue-as-input form today. Define the ir-block grammar for an lvalue store before
  Phase 3.
- **I2.** Phase 5's `%ref`-input mechanism for passing `ClassInfo`/`MOP::Class` through
  the corpus → `build_graph_from_ir` → LLVM is undefined. Phase 5 is unexecutable
  without this syntax. Specify it (and confirm it does NOT wire the stalled MOP
  migration internals).
- **I3.** G.4 (parser→LLVM equivalence gate) is AMBIGUOUS: either it is the vacuous
  corpus-rewrite check (canonical-shaped ir-blocks = the same corpus run, no new test)
  OR a real `Actions.pm → NodeFactory → LLVM → lli` test (blocks on the parser emitting
  corpus idioms — OUT of scope/unscheduled). The plan conflates them. Decide: G.4 = the
  corpus-now-uses-canonical-nodes assertion (automatic), and a TRUE parser-equivalence
  test is a separate FUTURE gate when the parser is wired — not part of this work.
- **I4.** The nested-ref ArrayLiteral/MakeArrayRef fold (R8: `ArrayLiteral` holds
  `ArrayRef`-typed slots) — folding both into one `ArrayRef` collapses
  construct-vs-ref when elements are themselves refs. Resolve this design question
  BEFORE Phase 2, not "during execution."
- **I5.** F10 deferral has NO filed issue (CLAUDE.md: unlabeled deferrals become
  drift). File the F10 (Context cohesion + control-processor duplication) follow-up
  issue as part of Phase G acceptance.
- **I6.** No pre-Phase-G failure BASELINE. Phase G tightens the gate; without a
  documented baseline (full `./prove` before Phase G, incl. the known
  codegen-byte-compat / class-scope-vars pre-existing failures), a Phase-G regression
  can't be distinguished from a pre-existing failure. Require the baseline as Phase G
  step 0.
- **I7.** Optimizer dual-contract risk underweighted: the corpus ir-blocks are BOTH a
  lowering spec AND the optimizer's output-shape contract (corpus_dual_contract). The
  plan's "behavior blocks unchanged → zero risk" framing misses that the SHAPE
  contract lives in the ir-blocks. Audit whether any optimizer/codegen test uses the
  corpus ir-blocks as SHAPE oracles; account for updating them.
- **I8.** Narrow namespace move "alongside Phase 0" creates rework: Phase G tests are
  written against `Chalk::IR::Target::LLVM` then immediately renamed. Do the namespace
  move BEFORE Phase G (so all new tests use the final name), or accept the rework
  explicitly.

## Minor
- M1. S3 (no lib→test dep): confirm G.1's MISCOMPILE-unification lands in the HARNESS
  (t/lib), not in `LLVM.pm` production code.
- M2. `lli` path is hardcoded in LLVMDriver.pm:16 + LLVMGapMap.pm:32; Phase G runs lli
  harder — note the llvm-15 environmental dependency so RED-fails aren't misread.
- M3. "Independently revertible" should be validated (a phase's single commit `git
  revert`s to GREEN, not just compiles) — especially the combined corpus+lowering+delete
  commits.
- M4. (folded into C3/C4) the revertibility claim is already broken by Phase 4↔5.

## Net recommendation
The plan needs a revision pass addressing C1–C5 (sequencing + decomposition +
the GREEN-invariant correction + the F8 reality) and I1–I4 (the unspecified ir-block
syntaxes + the nested-ref + G.4 ambiguity) BEFORE it is executable. C1, C3, C4, C5 are
structural (re-sequence + decompose); C2 is a correctness correction to the plan's own
claim; I1/I2 are missing specifications that block Phases 3 and 5. None invalidates the
plan's direction (converge to single IR + harden the gate); they fix HOW.
