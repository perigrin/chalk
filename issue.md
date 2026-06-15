---
title: "4b-1: single-exit normalization in FromOptree (the 4b blocker)"
state: pending
urgency: normal
milestone: v0.1
blocks:
- 019ecd59-f6cf-7565-b401-d09ff11dce37
- 019ecd59-f712-78fb-8e6a-2ca431b76531
- 019ecd59-f79d-79a9-9c58-34c8476b77f0
- 019ecd59-f7df-738b-ae3d-b4b270fc3cc1
- 019eaa51-bcfe-76b6-a02d-a23a65bd7498
created: 2026-06-15T22:14:30.585102665Z
updated: 2026-06-15T22:23:43.284909069Z
---

Producer-side. SoN::FromOptree returns the graph at the FIRST return op (FromOptree.pm:290-304) / early-return subs are swallowed by B::SoN.pm:102 catch{}; LLVM _method_body_root dies on >1 Return. Rework the return/leavesub handler to DEFER: collect each return value+control edge, merge via the EXISTING Region+Phi machinery (make_cfg If :107, sim->merge Region :130, Phi :197, _walk_branch :750 — confirmed not loop-only 2026-06-15). Verify via the corpus harness: an early-return sub flows source->B::SoN->JSON->Chalk->backend==perl. Scope: docs/plans/2026-06-15-phase4b-scope.md. Blocks all other 4b items.
