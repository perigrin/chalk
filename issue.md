---
title: "4b-1: single-exit normalization in FromOptree (the 4b blocker)"
state: pending
urgency: normal
milestone: v0.1
blocks:
- 019ecd59-f6cf-7565-b401-d09ff11dce37
created: 2026-06-15T22:14:30.585102665Z
updated: 2026-06-15T22:14:59.134871284Z
---

Producer-side. SoN::FromOptree returns the graph at the FIRST return op (FromOptree.pm:290-304) / early-return subs are swallowed by B::SoN.pm:102 catch{}; LLVM _method_body_root dies on >1 Return. Rework the return/leavesub handler to DEFER: collect each return value+control edge, merge via the EXISTING Region+Phi machinery (make_cfg If :107, sim->merge Region :130, Phi :197, _walk_branch :750 — confirmed not loop-only 2026-06-15). Verify via the corpus harness: an early-return sub flows source->B::SoN->JSON->Chalk->backend==perl. Scope: docs/plans/2026-06-15-phase4b-scope.md. Blocks all other 4b items.
