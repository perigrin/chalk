# Prior art: how production compilers merge a branch with effects

**Date:** 2026-08-13
**Method:** deep-research, 107 agents, adversarially verified
**Poses:** docs/research/2026-08-13-arm-content-inspection-measured.md

## Summary

No production Sea-of-Nodes or SSA compiler surveyed inspects a branch arm's contents to decide whether to build control flow — control flow is built unconditionally at every branch, and the effect/purity decision is made per-NODE by static operator type, never per-ARM by scanning. Graal's paper example erects a full If/Begin/End/Merge/Phi diamond even when one arm is a bare value copy; TurboFan threads a single effect chain through every node whose operator declares an effect input; Braun et al.'s on-the-fly SSA construction places phis solely on variable reads, consulting only `sealed` status and `|block.preds|`. Diamond-to-select collapse is universally a LATER pass over finished IR (LLVM's `foldTwoEntryPHINode`, Graal's `IfNode.simplify`/`conditionalNodeOptimization`), and its preconditions are (a) a single uniform per-INSTRUCTION safety predicate, `isSafeToSpeculativelyExecute`, which is strictly stronger than effect-freedom (it also rejects faulting-but-pure ops like division and loads) and is context-sensitive, plus (b) an independent instruction-count/cost budget — never a disjunction of effect-kind predicates. LLVM's own developers publicly call their five overlapping content-inspecting speculation gates "a horrible inconsistent mess," and V8's implementers migrated off Sea of Nodes citing manual effect-chain bookkeeping as error-prone (a months-lived shipped bug). The evidence points hard at path (b): remove the discriminator, always build control flow, collapse later — and note Graal's elegant shortcut, where because effectful nodes are fixed BY TYPE, the collapse test is just "is the arm empty?", which subsumes the side-effect question without ever asking it.

## Findings

### Q1 ANSWERED — NO production SoN/SSA IR builder inspects a branch arm's contents to choose control flow vs. value select. Control flow is erected unconditionally at every branch; the only decision the builder makes is per-NODE (can THIS operator float?), determined by static node type, never by scanning a region.

**Confidence:** high

Graal (Duboscq et al., APPLC 2013) Figure 2 shows an If with two Begin successors, two Ends feeding a Merge, and a Phi on that Merge — for source `if (cond) { result = value1 + value2; } else { result = value2; }` whose ELSE ARM IS A BARE VALUE COPY WITH NO EFFECTS AT ALL. A full diamond is built anyway. Line 125 is universal: 'Each block of the control-flow graph begins with a Begin node.' Current Graal master corroborates: BytecodeParser.genIfNode unconditionally returns `new IfNode(condition, trueSuccessor, falseSuccessor, profileData)` — no arm scan, no select-vs-controlflow choice at parse time. The classification is per-node and typed: FixedNode.verifyNode() asserts 'FixedNode should not float'; StateSplit.hasSideEffect() is a boolean on the node's own class. Formalization (arXiv:2107.01815, ATVA 2021) states the rule flatly: 'Expressions with potentially observable side-effects, such as method invocations or field accesses, are incorporated into the control-flow graph' — enumerated BY NODE CLASS (ValuePhiNode, InvokeNode, NewInstanceNode, LoadFieldNode), not by region scan. V8/TurboFan is the same shape: effect-chain membership is decided at node construction by a static operator property — `bool has_effect = op->EffectInputCount() == 1;` in bytecode-graph-builder.cc — 'a single effect chain (which splits on branches, and merges back when the control flow merges) which is used for ALL effectful operations.' This is a direct counter-example to Chalk's _arm_has_* design.

Sources:
- https://ssw.jku.at/General/Staff/GD/APPLC-2013-paper_12.pdf
- https://arxiv.org/pdf/2107.01815
- https://v8.dev/blog/leaving-the-sea-of-nodes
- https://raw.githubusercontent.com/oracle/graal/master/compiler/src/jdk.graal.compiler/src/jdk/graal/compiler/java/BytecodeParser.java
- https://link.springer.com/content/pdf/10.1007/978-3-642-37051-9_6.pdf

### Q2 PART 1 — The collapse happens in a LATER optimization pass over already-built control flow, in both LLVM and Graal. The pass takes an EXISTING two-entry PHI / EXISTING If as input and recovers the diamond from existing structure; it is structurally incapable of running before the CFG exists.

**Confidence:** high

LLVM: the option's own description states the job — 'Control the maximal total instruction cost that we are willing to speculatively execute to fold a 2-entry PHI node into a select (default = 4)'. foldTwoEntryPHINode's doc comment: 'Given a BB that starts with the specified two-entry PHI node, see if we can eliminate it', and its body calls `GetIfCondition(BB, IfTrue, IfFalse)` which pattern-matches predecessors ALREADY ending in a conditional branch. It lives in Transforms/Utils (an optimization pass), dispatched from the pass's simplify loop over existing CondBrInst/PHINode (foldTwoEntryPHINode at :9220, speculativelyExecuteBB at :8915/:8924, foldBranchToCommonDest at :8868). Graal: select formation is IfNode.simplify(SimplifierTool) / removeOrMaterializeIf / conditionalNodeOptimization ('Try to optimize this as if it were a ConditionalNode') — a later phase over a finished graph. NAME THE PASSES: LLVM SimplifyCFG (foldTwoEntryPHINode, speculativelyExecuteBB, foldBranchToCommonDest, hoistCommonCodeFromSuccessors [formerly HoistThenElseCodeToIf], SimplifyCondBranchToCondBranch); Graal CanonicalizerPhase + ConditionalEliminationPhase + IfNode.simplify; Graal FloatingReadPhase for floating pinned memory reads later. CAVEAT: Clang's frontend has ONE narrow construction-time select path (CGExprScalar.cpp isCheapEnoughToEvaluateUnconditionally, gated on isEvaluatable/constants) — but note its polarity: a conservative provably-side-effect-free WHITELIST, not an enumerated blacklist of effect kinds.

Sources:
- https://llvm.org/doxygen/SimplifyCFG_8cpp.html
- https://raw.githubusercontent.com/llvm/llvm-project/main/llvm/lib/Transforms/Utils/SimplifyCFG.cpp
- https://lists.llvm.org/pipermail/llvm-dev/2018-November/127769.html
- https://raw.githubusercontent.com/oracle/graal/master/compiler/src/jdk.graal.compiler/src/jdk/graal/compiler/nodes/IfNode.java

### Q2 PART 2, THE LOAD-BEARING ANSWER — The soundness precondition is a SINGLE uniform per-INSTRUCTION predicate, isSafeToSpeculativelyExecute, whose contract is exactly 'no effects besides calculating the result AND no undefined behavior'. It is STRICTLY STRONGER than effect-freedom: it also rejects pure-but-faulting instructions (div-by-zero, INT_MIN/-1, loads from non-provably-dereferenceable pointers, malloc/alloca, terminators, PHIs). A gate that only asks 'does this arm have a call/store/die' is therefore UNSOUND even if its effect enumeration were complete.

**Confidence:** high

ValueTracking.h verbatim: 'Return true if the instruction does not have any effects besides calculating the result and does not have undefined behavior. This method never returns true for an instruction that returns true for mayHaveSideEffects; HOWEVER, THIS METHOD ALSO DOES SOME OTHER CHECKS IN ADDITION. It checks for undefined behavior, like dividing by zero or loading from an invalid pointer... It checks for malloc and alloca because speculatively executing them might cause a memory leak. It also returns false for instructions related to control flow, specifically terminators and PHI nodes.' That is LLVM stating the claim's structure in its own words: effect-freedom NECESSARY but NOT SUFFICIENT. The implementation confirms it is not doc aspiration — isSafeToSpeculativelyExecuteWithOpcode (ValueTracking.cpp:7380ff) has `default: return true` then carves out UDiv/URem (false unless divisor is known-nonzero constant), SDiv/SRem (also rejects INT_MIN/-1), Load (false unless isDereferenceableAndAlignedPointer proves it), Call (readnone+nounwind is EXPLICITLY NOT ENOUGH — demands Callee->isSpeculatable()). udiv/sdiv/load all have mayHaveSideEffects()==false and are rejected anyway. FOR CHALK CONCRETELY: a collapse pass gated on 'no call / no store / no die' would still wrongly hoist a Perl division, a modulus, or an element read of a possibly-nonexistent slot. TWO FURTHER CAVEATS FOR ANYONE IMPLEMENTING THE COLLAPSE: (a) the same comment warns 'This method can return true for instructions that read memory; for such instructions, moving them may change the resulting value' — safety alone does NOT establish value-preservation under hoisting; (b) LLVM bug 108854 reports the predicate is itself unsound as used from SimplifyCFG (may approve a load via dereferenceable attributes discarded when the instruction moves).

Sources:
- https://raw.githubusercontent.com/llvm/llvm-project/main/llvm/include/llvm/Analysis/ValueTracking.h
- https://raw.githubusercontent.com/llvm/llvm-project/main/llvm/lib/Analysis/ValueTracking.cpp
- https://llvm.org/doxygen/ValueTracking_8h_source.html
- https://docs.hdoc.io/hdoc/llvm-project/f80202368C2F98EBE.html

### Q2 PART 3 — Safety and profitability are TWO INDEPENDENT GATES. Beyond the safety predicate, LLVM enforces a separate tunable instruction-count/cost budget; exceeding it aborts the fold even when every instruction is provably safe. Critically, ALL the gates are count-or-cost budgets over the whole arm — there is NO disjunction of effect-kind predicates anywhere in SimplifyCFG.

**Confidence:** high

dominatesMergePoint structure: safety is an unconditional early-out at its own return site — `if (!isSafeToSpeculativelyExecute(I, InsertPt, AC)) return false;` — and the budget is a SEPARATE, later condition with its own return — `if (Cost > Budget && (!SpeculateOneExpensiveInst || !AggressiveInsts.empty() || Depth > 0 || !Cost.isValid())) return false;`. Documented cost model: 'The cost for most non-trapping instructions is defined as 1 except for Select whose cost is 2... If that cost is greater than Budget, false is returned.' Budgets confirmed line-by-line in current main: speculativelyExecuteBB `if (SpeculatedInstructions > 1) return false;` (:3306) plus per-instruction cap `PHINodeFoldingThreshold * TCC_Basic` (:3317-18); foldBranchToCommonDest `if (NumBonusInsts > BonusInstThreshold * ...) return false;` (:4320-24, with `if (&I == Cond) continue;` at :4301 giving the implicit '1+'); SimplifyCondBranchToCondBranch `if (&*BB->begin() != BI) return false;` (:4802-08, literally empty-except-branch); foldTwoEntryPHINode `InstructionCost Budget = TwoEntryPHINodeFoldingThreshold * TCC_Basic;` (:3903-24). NOTE THE ASYMMETRY: safety is unconditional, profitability is overridable (SpeculateOneExpensiveInst admits one expensive instruction at Depth 0 with empty AggressiveInsts). ALSO: isSafeToSpeculativelyExecute is CONTEXT-SENSITIVE — 'If the CtxI is specified this method performs context-sensitive analysis and returns true if it is safe to execute the instruction immediately before the CtxI' — so the answer is NOT a property of the arm alone, which is precisely what an arm-content-scanning discriminator assumes. SimplifyCFG's dominatesMergePoint does pass the merge insertion point as CtxI, so this is the production path, not vestigial plumbing.

Sources:
- https://raw.githubusercontent.com/llvm/llvm-project/main/llvm/lib/Transforms/Utils/SimplifyCFG.cpp
- https://llvm.org/doxygen/SimplifyCFG_8cpp.html
- https://lists.llvm.org/pipermail/llvm-dev/2018-November/127769.html

### Q3 ANSWERED — Braun et al. (2013) on-the-fly SSA construction places phis purely on demand when a variable is READ, never by inspecting block contents. The two facts the decision consults are structural CFG properties only: whether the block is SEALED, and |block.preds|. Sealing is defined by predecessor completeness and is explicitly DECOUPLED from 'filling' (having all instructions) — a block can be sealed before it is filled. There is no principled reason a translator ever needs the arm-content question.

**Confidence:** high

Paper verbatim (lines 86-94): 'Cytron et al.'s algorithm is an eager approach operating in forwards direction... In contrast, our algorithm works backwards in a lazy fashion: Only when a variable is used, we query its reaching definition. If it is unknown at the current location, we will search backwards through the program. We insert phi functions at join points in the CFG along the way.' Algorithm 2 (readVariableRecursive) branches on exactly two things: `if block not in sealedBlocks` -> operandless Phi into incompletePhis; `else if |block.preds| = 1` -> '# Optimize the common case of one predecessor: No phi needed', recurse into sole predecessor; else -> Phi + addPhiOperands. NO content predicate (store/call/die/effect) appears anywhere in Algorithms 1-4. Sealing definition (line 278): 'We call a basic block sealed if no further predecessors will be added to the block'; line 280: 'Note that a sealed block is not necessarily filled.' sealBlock (Alg. 4) iterates incompletePhis and a set — never the instruction list. Figure 3's while/if seal-and-fill orderings are determined by CFG SHAPE alone. Prunedness — the one property that superficially seems to need use/liveness knowledge — EMERGES FROM LAZINESS rather than from inspection: 'We only create phi functions on demand when a user asks for it... so our construction naturally produces a program in pruned SSA form.' SCOPE CAVEAT, important: Braun models LOCAL SCALAR VARIABLES only; the paper does not treat memory, side effects, or effect phis at all. Do not infer memory-phi behavior from this claim — see the next finding for that.

Sources:
- https://link.springer.com/content/pdf/10.1007/978-3-642-37051-9_6.pdf
- https://c9x.me/compile/bib/braun13cc.pdf

### Q4 ANSWERED — Memory/effect phis are placed by the SAME structural machinery as value phis, uniformly at control-flow joins, NOT conditionally on detecting a store. Graal's MemoryPhiNode is a subclass of PhiNode attached to the same AbstractMergeNode; V8 inserts an EffectPhi at every control merge unconditionally. 'Does this arm contain an element store' is a question the mature implementations never ask.

**Confidence:** high

Graal master: `public final class MemoryPhiNode extends PhiNode implements SingleMemoryKill` — memory phis ARE value phis, attached via the same `@Input(Association) protected AbstractMergeNode merge;` and read via the same `valueAt(AbstractEndNode pred)`. LoopBeginNode extends AbstractMergeNode precisely so phi handling is identical for loop headers and ordinary merges (2013 paper: 'Since LoopBegin nodes merge control flow, LoopBegin node is a subclass of Merge node... the interface used to relate phi nodes and merge nodes works in the same way whether it is a phi of a loop or of a normal merge'). Placement in the frontend is positional and content-free: FrameStateBuilder.merge iterates locals[]/stack[]/lockedObjects[] slot-by-slot and creates a phi wherever two incoming values differ — no predicate over block contents. V8: 'Node* effect = builder()->MergeEffect(GetEffectDependency(), other->GetEffectDependency(), control);' inserts a kEffectPhi at EVERY control merge. THE ELEGANT MECHANISM CHALK SHOULD STEAL: because effectful nodes are FIXED BY TYPE in Graal, an arm containing one is simply NOT EMPTY — so IfNode's select-formation preconditions are purely structural (`trueSuccessor().next() instanceof AbstractEndNode && falseSuccessor().next() instanceof AbstractEndNode`, `anchored().isEmpty()`, `hasNoUsages()`) and the emptiness test SUBSUMES the side-effect question without ever asking it. Notably hasSideEffect/StateSplit/canDeoptimize do NOT appear in IfNode's select-formation path. TIMING CAVEAT: Graal builds memory READS pinned to control flow and floats them LATER — 'we create floating nodes for all nodes where this does not require any special analysis or dependency creation. Some operations that cannot immediately be represented as floating nodes, such as memory read operations, are transformed into floating nodes by later optimization phases that insert the appropriate dependencies' (still true in master: FloatingReadPhase). That is build-conservatively-then-relax, exactly path (b).

Sources:
- https://raw.githubusercontent.com/oracle/graal/master/compiler/src/jdk.graal.compiler/src/jdk/graal/compiler/nodes/memory/MemoryPhiNode.java
- https://raw.githubusercontent.com/oracle/graal/master/compiler/src/jdk.graal.compiler/src/jdk/graal/compiler/nodes/PhiNode.java
- https://ssw.jku.at/General/Staff/GD/APPLC-2013-paper_12.pdf
- https://chromium.googlesource.com/v8/v8/+/refs/heads/main/src/compiler/bytecode-graph-builder.cc
- https://arxiv.org/pdf/2107.01815

### Q6 ANSWERED — Content-inspection approaches HAVE been tried, and their documented failure mode is precisely Chalk's: multiple overlapping gates each inspecting arm contents with a DIFFERENT predicate, so a single arm gets rejected by every gate for a different incidental reason, and outcomes depend on gate ordering rather than on the arm. An LLVM contributor RFC'd this publicly as 'a horrible inconsistent mess'.

**Confidence:** high

John Brawn, llvm-dev, 15 Nov 2018, subject '[RFC] SimplifyCFG block speculation is a horribly inconsistent mess': 'SimplifyCFG does block speculation, which is currently a horrible inconsistent mess. There are five functions (that I've found) that do this, with a lot of overlap in what they handle and also some restricted in ways that others aren't without much consistency.' His worked example @fn1: ONE block bb1, rejected by BOTH candidate routines for UNRELATED reasons — 'no speculation happens because the two function which could possibly do it are SpeculativelyExecuteBB, which can't do it because %cmp2 is an fcmp, and SimplifyCondBranchToCondBranch, which can't do it because bb1 isn't empty'. The contrast case @fn2 (same shape, %cmp2 hoisted so bb1 becomes empty) DOES speculate. His per-routine table shows genuinely bidirectional divergence (phis UPDATED in one routine vs. phis turned into SELECTS in another; fcmp banned in one and unrestricted in another). His other examples (@fn3-@fn5, @fn6-@fn8) document ORDER-DEPENDENCE and threshold inconsistency among the same gates — Chalk's 'first predicate to answer wins' pathology, in a production compiler. The 2018 unification proposal was NOT completed (author flagged the obstacle himself: 'Doing this changes the order that blocks are speculated, giving worse results in some cases') and all five routines plus their divergent thresholds still exist in current main. INDEPENDENT SECOND DATA POINT: V8's implementers on manual effect/control bookkeeping — 'History has shown that managing both the effect and control chains manually is error prone, hard to read and hard to maintain' — with a concrete shipped defect: managing 3 effect chains in ReduceNamedAccess, 'So easy that we indeed got it wrong initially, and only realized our mistake after a few months' (crbug.com/41470351, fixed crrev.com/c/1749902). VERDICT FOR CHALK: this is prior art on why content-inspection gating is a bad idea, not evidence that Chalk merely implemented a legitimate technique badly.

Sources:
- https://lists.llvm.org/pipermail/llvm-dev/2018-November/127769.html
- https://raw.githubusercontent.com/llvm/llvm-project/main/llvm/lib/Transforms/Utils/SimplifyCFG.cpp
- https://v8.dev/blog/leaving-the-sea-of-nodes

### RECOMMENDATION — Take path (b): delete the discriminator, always build control flow in void context, add a later collapse pass. The four _arm_has_* predicates are not fixable by adding a fifth, because the three bugs and the measured overlap (101/117 shapes scanned by >1 predicate, 60 by all four, 44 arms with multiple simultaneous effect kinds) are symptoms of the disjunctive-content-gate structure itself, which is the exact failure mode LLVM documented.

**Confidence:** high

Three structural reasons the discriminator cannot be repaired in place. (1) The nested-if bug is UNFIXABLE by predicate refinement — a nested `if` inside an arm compiles to the same `and` op as a statement modifier, so no content predicate at that point in the walk can distinguish them; the arm-content question is unanswerable at construction time, which is why no surveyed compiler asks it. (2) A disjunction of effect kinds is the wrong SHAPE regardless of completeness — LLVM asks ONE whole-instruction safety question (isSafeToSpeculativelyExecute) plus ONE scalar budget, never 'is this a call OR a store OR a terminator'; and that single question is strictly stronger than effect-freedom (rejects div/load/malloc/terminator/PHI), so Chalk's enumeration would be unsound even if complete. (3) Chalk's measured overlap (44 shapes where multiple predicates are simultaneously true, first-caller-wins) IS Brawn's @fn1 pathology. CONCRETE DESIGN FOR THE COLLAPSE PASS, cheapest sound version: adopt Graal's typing trick rather than LLVM's cost machinery. Make effectfulness a per-NODE static property at construction (effectful op => fixed node on the effect chain), then the collapse precondition reduces to the structural test Graal actually uses — both arms empty of fixed nodes, no anchored usages — which subsumes the side-effect question without ever scanning for effect kinds. Add ONE speculation-safety predicate over any residual pure-but-faulting Chalk ops (division, modulus, possibly-nonexistent element read, anything that can die) modelled on isSafeToSpeculativelyExecute. Skip the cost budget initially: it is a PROFITABILITY gate, independent of soundness, and LLVM's own developers say the inconsistent thresholds are the mess. Add it when select-formation measurably regresses, not before.

Sources:
- https://lists.llvm.org/pipermail/llvm-dev/2018-November/127769.html
- https://raw.githubusercontent.com/oracle/graal/master/compiler/src/jdk.graal.compiler/src/jdk/graal/compiler/nodes/IfNode.java
- https://raw.githubusercontent.com/llvm/llvm-project/main/llvm/include/llvm/Analysis/ValueTracking.h
- https://ssw.jku.at/General/Staff/GD/APPLC-2013-paper_12.pdf


## Not answered

**Q5 (Perl-specific prior art) returned nothing.** No surveyed source documents
how RPerl, Perlito, B::CC, the perl5-to-JVM efforts, or perl's own rpeep
distinguish `if (C) { BODY }` from `BODY if C` — both being `and` with
OPf_WANT_VOID. Recorded as a genuine gap, not as evidence of absence: it may
simply be that nobody needed to ask, which is what Q1's answer predicts.

## What this changes

The question was "fix the discriminator, or delete it". The answer is delete it,
and the reasoning is not merely that the predicates overlap:

1. **The nested-if case is UNANSWERABLE at construction time.** A nested `if`
   and a statement modifier are the same op. No predicate refinement can
   separate them, which is why no surveyed compiler asks the question there.

2. **A disjunction of effect kinds is the wrong SHAPE even if complete.** LLVM
   asks ONE whole-instruction question (`isSafeToSpeculativelyExecute`) plus ONE
   cost budget. That question is STRICTLY STRONGER than effect-freedom: it also
   rejects pure-but-faulting operations — division, loads from
   non-provably-dereferenceable pointers, malloc/alloca, terminators, phis.
   Chalk's enumeration would be unsound even if it named every effect kind,
   because a pure faulting op passes all four `_arm_has_*` predicates.

3. **Graal's shortcut is the one to copy.** Because effectful nodes are FIXED BY
   TYPE, the collapse test degenerates to "is the arm empty?" — the side-effect
   question is subsumed structurally and never asked.

## What path (b) costs, concretely

- Build If + Proj + Region + memory Phi at EVERY void-context branch. Delete the
  four `_arm_has_*` predicates and their 15 call sites.
- Add a later collapse pass over the finished graph. Its gate is one per-node
  speculation predicate plus one cost budget — NOT a list of effect kinds.
- Chalk already has the ingredient Graal relies on: `%STATEMENT_EFFECT_OPS`
  classifies effectful ops by TYPE. If that classification is the authority,
  "is this arm collapsible" becomes "does it contain any fixed node", which is
  the structural question rather than the content one.

Unverified and load-bearing before building: whether Chalk's effect
classification is actually complete and type-based, or whether it too has
enumeration gaps. The `Coerce[Unknown]` and `Scalar`-as-placeholder findings
this session suggest checking rather than assuming.
