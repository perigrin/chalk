---
title: "Reconciliation 1/3: namespace move + Phase G (gate hardening)"
state: done
urgency: normal
milestone: codegen-harness
blocks:
- 019eaacc-4dd8-7a5f-b095-29fc817b6442
created: 2026-06-09T05:12:56.506078225Z
updated: 2026-06-09T06:19:13.402075569Z
sessions:
- start_sha: d3fb9069fb70b3c25454813e6f93385dbe7d3ad1
  end_sha: 5b867a6aa3bd1f25ee6aab45f0e211044dee233e
  commits: 8
  started_at: 2026-06-09T05:15:54.410487086Z
  ended_at: 2026-06-09T06:19:13.402075569Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-06-09T05:15:54.410487086Z
- state: done
  actor: human:git-zhi
  timestamp: 2026-06-09T06:19:13.402075569Z
observed_paths:
- docs/plans/2026-06-08-ir-taxonomy-reconciliation.md
- lib/Chalk/Bootstrap/Target.pm
- lib/Chalk/Target/LLVM.pm
- lib/Chalk/Target.pm
- t/bootstrap/codegen-harness/g1-miscompile-classification.t
- t/bootstrap/codegen-harness/g2-libperl-free-guard.t
- t/bootstrap/codegen-harness/type-tag.t
- t/bootstrap/corpus/mdtest.t
- t/bootstrap/ir/elaborate.t
- t/bootstrap/ir/llvm-array-hash.t
- t/bootstrap/ir/llvm-bool-truthiness-guard.t
- t/bootstrap/ir/llvm-coerce-bool-str.t
- t/bootstrap/ir/llvm-coerce-str.t
- t/bootstrap/ir/llvm-lowering.t
- t/bootstrap/ir/llvm-method-body-needs.t
- t/bootstrap/ir/llvm-mop-classes.t
- t/bootstrap/ir/llvm-reassign-soundness.t
- t/bootstrap/ir/llvm-typed-3c.t
- t/bootstrap/ir/llvm-undef-defined-or.t
- t/bootstrap/ir/llvm-undef-repr-guard.t
- t/fixtures/codegen-goldens/Chalk__Bootstrap__Target.pl.golden
- t/lib/Chalk/CodeGen/Harness/LLVMDriver.pm
- t/lib/Chalk/CodeGen/Harness/LLVMGapMap.pm
- t/lib/Chalk/CodeGen/Harness/MdtestCorpus.pm
---

-
