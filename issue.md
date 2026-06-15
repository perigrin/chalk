---
title: "Phase 4: B::SoN as trusted IR/MOP producer (directional, verified through harness)"
state: in-progress
urgency: normal
milestone: codegen-harness
blocked_by:
- 019eaa51-bd60-73ee-bec0-6bb0ba204e3b
- 019eb316-0c85-7a68-87fc-f0c1cd221b5a
- 019eb6ff-c505-71f7-9665-5e087be277fe
- 019ecd59-bbb9-7f8e-8958-8a218a8f6546
- 019ecd59-f688-732d-a2f5-4cf410439b04
- 019ecd59-f6cf-7565-b401-d09ff11dce37
blocks:
- 019eaa51-b9eb-7bc5-bee4-ca6140dc8b81
created: 2026-06-09T02:59:04.062678084Z
updated: 2026-06-15T22:23:44.451365343Z
sessions:
- start_sha: 125deda16f98e24471678aaa7f4b363e237ed4cd
  end_sha: ""
  commits: 0
  started_at: 2026-06-14T03:58:25.906947341Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-06-14T03:58:25.906947341Z
---

Scoping brief: docs/plans/2026-06-12-phase4-bson-brief.md. Stage 4a (seam re-audit) DONE 2026-06-14: docs/plans/2026-06-14-phase4a-seam-reaudit.md.

4a HEADLINE (corrects April's stale "70/76"): today's IR = 84 node classes; SoN::FromOptree actually EMITS ~40. The class-name mirror (77/84) is NOT the contract. Zero R3-deleted nodes are produced (B::SoN is behind the deleted vocabulary, never coupled). Gap set: RegexCapture, EnvRead, Coerce, ExpressionList, ListAssign, CompoundAssign, Match/NotMatch binding, Interpolate, StructRef/FieldAccess + the ENTIRE MOP/class tier.

THE THREE OPEN DECISIONS — DECIDED in 4a (grounded):
(a) Conversion locus = KEEP THE JSON SEAM. Chalk's from_json already reconstructs per-call #N identity through Chalk's NodeFactory; B::SoN's own factory hash-conses (wrong identity), so in-process construction would drag Chalk's IR tree into perl5-son AND need the identity rules re-imported. JSON isolates it.
(b) MOP emission = DECLARATIVE JSON section replayed Chalk-side via declare_*/seal. Chalk::MOP isn't cheaply loadable from perl5-son (pulls Graph/NodeFactory/Bindings); the corpus MOP::* vocabulary is the replay precedent.
(c) Multi-exit bodies = NORMALIZE TO SINGLE-EXIT in FromOptree (merge returns via Region+Phi), NOT a gap-map entry.

SINGLE BIGGEST 4b BLOCKER (new finding, double-sided): multi-exit/early-return bodies. FromOptree truncates at the FIRST return (FromOptree.pm:290-304) or the whole sub is silently swallowed (B::SoN.pm:102 catch{}); LLVM _method_body_root DIES on >1 Return (LLVM.pm:360-363). Real lib/ is early-return-heavy -> nothing non-trivial flows until this is fixed. 4b starts here.

STILL-OPEN DEBTS (re-measured): field writes dropped (probe confirmed: $n+=1 -> FieldAccess;Add;Return, store absent); no MOP emission (largest 4c gap); PadAccess targ bug present (cosmetic-but-real, cross-graph identity); son-compare divergences are PURE node-ordering (not semantic) on its trivial-accessor corpus -- it does NOT certify the hard tiers; the mdtest corpus is the real work-list.

SHAPE: 4b computation slice (start: single-exit normalization; then field/element writes, CompoundAssign, increment modeling) -> 4c class tier (declarative MOP JSON + Call.class_name) -> 4d regex/host/try (RegexCapture wiring, EnvRead, TryCatch) gated on 019eb6ff item 1. Gate 0 (019eb6ff) CLOSED. Branch sound to build on (whole-branch review 2026-06-13, 0 Critical).
