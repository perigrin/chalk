---
title: "4b-3: validate the producible-now corpus slice end-to-end"
state: pending
urgency: normal
milestone: v0.1
blocked_by:
- 019ecd59-bbb9-7f8e-8958-8a218a8f6546
- 019ecd59-f688-732d-a2f5-4cf410439b04
created: 2026-06-15T22:14:45.711357698Z
updated: 2026-06-15T22:15:00.217350848Z
---

Harness. The 4a gap map marks arithmetic, variables A1/A4/C1, logical L1-L4, strings S1-S3, control-flow D1/D6/D2-D3(suspect), references R1-R5/R9-R11, statements, subs F1-F3 as producible-now. Run each corpus perl source through the full B::SoN->JSON->Chalk->backend path; each landing ==perl is a real green, each that does not is a newly-localized producer bug. This is the gap map turning red->green = the bulk of 4b value. Loop-Phi correctness (D2/D3/D5) verified here; if wrong it joins the work list. Scope: docs/plans/2026-06-15-phase4b-scope.md
