---
title: "GAP group 6: regex sub-compiler (pattern to matcher)"
state: done
urgency: normal
milestone: codegen-harness
blocked_by:
- 019eaa51-c30a-70e5-8fbe-2f9732760c63
- 019eaacc-4df6-7b46-915d-bd2aa1a4064f
blocks:
- 019eaa51-bd3e-7b89-b376-c13304da68f7
created: 2026-06-09T02:59:05.997424403Z
updated: 2026-06-10T07:59:21.070430256Z
sessions:
- start_sha: f4149ea4cdf412c343610792324cddc1e34ba8d7
  end_sha: 9188549ab59cf30f4f1b1de5460976816b027276
  commits: 43
  started_at: 2026-06-09T02:59:46.255309218Z
  ended_at: 2026-06-10T07:59:21.070430256Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-06-09T02:59:46.255309218Z
- state: done
  actor: human:git-zhi
  timestamp: 2026-06-10T07:59:21.070430256Z
observed_paths:
- docs/architecture/sea-of-nodes-ir.md
- docs/architecture/typed-ir-representation.md
- docs/plans/2026-06-08-ir-taxonomy-reconciliation.md
- lib/Chalk/Bootstrap/Target.pm
- lib/Chalk/IR/ClassInfo.pm
- lib/Chalk/IR/Graph/TypedInvariant.pm
- lib/Chalk/IR/MethodInfo.pm
- lib/Chalk/IR/Node.pm
- lib/Chalk/IR/Node/AdjustBlock.pm
- lib/Chalk/IR/Node/ArrayDeref.pm
- lib/Chalk/IR/Node/ArrayLiteral.pm
- lib/Chalk/IR/Node/ArrayRead.pm
- lib/Chalk/IR/Node/ArrayWrite.pm
- lib/Chalk/IR/Node/Call.pm
- lib/Chalk/IR/Node/ClassDecl.pm
- lib/Chalk/IR/Node/FieldDef.pm
- lib/Chalk/IR/Node/FieldWrite.pm
- lib/Chalk/IR/Node/HashDeref.pm
- lib/Chalk/IR/Node/HashLiteral.pm
- lib/Chalk/IR/Node/HashRead.pm
- lib/Chalk/IR/Node/HashWrite.pm
- lib/Chalk/IR/Node/MakeArrayRef.pm
- lib/Chalk/IR/Node/MakeHashRef.pm
- lib/Chalk/IR/Node/MethodCall.pm
- lib/Chalk/IR/Node/MethodDef.pm
- lib/Chalk/IR/Node/New.pm
- lib/Chalk/IR/Node/ScalarLen.pm
- lib/Chalk/IR/NodeFactory.pm
- lib/Chalk/IR/Target.pm
- lib/Chalk/Target/LLVM.pm
- lib/Chalk/Target.pm
- paad/architecture-reviews/2026-06-09-reconciliation-plan-crochet-assess.md
- paad/code-reviews/phase1-lateral-bindings-2026-06-09-18-52-00-af42bab2-R2-agentic.md
- paad/code-reviews/phase1-lateral-bindings-2026-06-09-22-43-09-ff9b4d08-R2reopen-agentic.md
- paad/code-reviews/phase1-lateral-bindings-2026-06-09-R1-agentic.md
- paad/code-reviews/phase1-lateral-bindings-2026-06-10-02-36-29-f94ea2a8-R3-agentic.md
- paad/code-reviews/phase1-lateral-bindings-2026-06-10-07-58-14-0eb83b94-G6-agentic.md
- t/bootstrap/codegen-harness/g1-miscompile-classification.t
- t/bootstrap/codegen-harness/g2-libperl-free-guard.t
- t/bootstrap/codegen-harness/target-hierarchy.t
- t/bootstrap/codegen-harness/type-tag.t
- t/bootstrap/corpus/mdtest.t
- t/bootstrap/corpus/regex.t
- t/bootstrap/ir/assign-lvalue-identity.t
- t/bootstrap/ir/build-classinfo.t
- t/bootstrap/ir/elaborate.t
- t/bootstrap/ir/llvm-aggregate-latent-fixes.t
- t/bootstrap/ir/llvm-array-hash.t
- t/bootstrap/ir/llvm-bool-truthiness-guard.t
- t/bootstrap/ir/llvm-call-method-dispatch.t
- t/bootstrap/ir/llvm-call-new-dispatch.t
- t/bootstrap/ir/llvm-classinfo-lowering.t
- t/bootstrap/ir/llvm-coerce-bool-str.t
- t/bootstrap/ir/llvm-coerce-str.t
- t/bootstrap/ir/llvm-lowering.t
- t/bootstrap/ir/llvm-method-body-needs.t
- t/bootstrap/ir/llvm-mop-classes.t
- t/bootstrap/ir/llvm-reassign-soundness.t
- t/bootstrap/ir/llvm-regex-match.t
- t/bootstrap/ir/llvm-regex-subst.t
- t/bootstrap/ir/llvm-str-const-collision.t
- t/bootstrap/ir/llvm-strpair-undeclared.t
- t/bootstrap/ir/llvm-typed-3c.t
- t/bootstrap/ir/llvm-undef-defined-or.t
- t/bootstrap/ir/llvm-undef-repr-guard.t
- t/bootstrap/ir/well-typed-graph.t
- t/bootstrap/perl-actions-tier-a.t
- t/corpus/mdtest/classes.md
- t/corpus/mdtest/references.md
- t/corpus/mdtest/regex.md
- t/fixtures/codegen-goldens/Chalk__Bootstrap__Target.pl.golden
- t/lib/Chalk/CodeGen/Harness/LLVMDriver.pm
- t/lib/Chalk/CodeGen/Harness/LLVMGapMap.pm
- t/lib/Chalk/CodeGen/Harness/MdtestCorpus.pm
---

-
