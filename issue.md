---
title: Value-cache staleness + statement-identity family (pre-B::SoN blocker)
state: done
urgency: normal
milestone: codegen-harness
blocks:
- 019eaa51-bcfe-76b6-a02d-a23a65bd7498
- 019eb6ff-c505-71f7-9665-5e087be277fe
created: 2026-06-10T19:50:27.205441995Z
updated: 2026-06-11T14:05:04.921657378Z
sessions:
- start_sha: 51724b453b35cf5c2137647d95ce2870c995d3e8
  end_sha: ca0fe1a188d2195391bb05876ac77f9871153ca1
  commits: 7
  started_at: 2026-06-11T12:36:06.777303469Z
  ended_at: 2026-06-11T14:05:04.921657378Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-06-11T12:36:06.777303469Z
- state: done
  actor: human:git-zhi
  timestamp: 2026-06-11T14:05:04.921657378Z
observed_paths:
- lib/Chalk/Bootstrap/Perl/Actions.pm
- lib/Chalk/IR/Graph.pm
- lib/Chalk/IR/NodeFactory.pm
- lib/Chalk/Target/LLVM.pm
- t/bootstrap/ir/assign-lvalue-identity.t
- t/bootstrap/ir/llvm-adjust-per-class-fn.t
- t/bootstrap/ir/llvm-phi-multiblock-arms.t
- t/bootstrap/ir/llvm-stale-value-cache.t
- t/bootstrap/ir/statement-effect-identity.t
- t/bootstrap/mop/build-graph-ifelse-trivial-phi.t
---

THE lateral-propagation axis, now with probe-proven reproducers (whole-branch review 2026-06-10, paad/code-reviews/...-256a9b37-branch-agentic.md; probes preserved in the report). ALL PRE-EXISTING pu architecture defects (verifier re-ran probes on pu) that bite on graph shapes the corpus deliberately avoids — they are the real blocker between hand-authored graphs and B::SoN feeding arbitrary parsed code (Phase 4/5). Fix BEFORE Phase 4 lands. See also memory phi_merge_strategy (the lateral-propagation-fix-first note).

- C1: lower_value cache excludes only PadAccess; a pure node OVER a PadAccess (Add(PadAccess,10)) caches stale across reassignment -> lli Int:22 vs perl Int:23, exit 0. Fix direction: exclude nodes whose transitive inputs include a mutable-location read (PadAccess/Subscript/FieldAccess), memoized per node.
- C2: identical Subscript/FieldAccess reads hash-cons+cache; read-after-element-store returns the pre-store value (Int:1 vs 9). The I2 fix covered write identity, not read staleness.
- C3: scalar-rebind Assign stays content-hash-consed; two identical rebind statements collapse to ONE node (Int:2 vs 3) + transient control self-loop in the Block fixup. Same family: CompoundAssign, builtin/sub Call, RegexSubst, TryCatch are in the Block fixup side-effect list but hash-consed — derive the factory identity list and the fixup list from ONE table.
- I5: four phi-arm/loop-init wiring sites lower values AFTER the host block terminator (invalid IR for multi-block values — Subscript scans, regex matchers). Fix: lower arms while the host block is open, re-capture incoming labels (the _lower_and/_lower_or pattern).
- I6: ADJUST bodies lowered on the MAIN ctx via local-flags; second new() of a class cache-hits the shared body nodes and emits NOTHING (Int:6 vs 107). Dead from the parse path today. Fix: ADJUST as a synthesized per-class fn in a fresh Context.
- Graph.pm merge/unmerge/nodes() key by content_hash — wrong-node substitution for per-call nodes + content-identical ORPHANS leak through the nodes() membership fallback (DCE roots on it). Key per-call nodes by id.
- Str-length phi pairs: when Str values cross phis the length is lost (currently safe — every Str is NUL-terminated post-C4-fix — but a length-phi design unblocks zero-copy views later).
