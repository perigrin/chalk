---
title: "LLVM purity follow-ups: F8 Coerce-route truthiness + I3 parser-to-LLVM equivalence gate"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-06-10T19:50:59.66274314Z
updated: 2026-06-10T19:50:59.66274314Z
---

Two parser-era follow-ups the reconciliation plan promised to file in G.0s note but never did (whole-branch review 2026-06-10):
- F8 section-2 purity: route &&/||/! truthiness through explicit Coerce(*->Bool) nodes instead of the current loud-die-on-non-Int (requires adding Coerce edges to logical.md ir-blocks). Plan ~244.
- I3 TRUE Actions.pm -> NodeFactory -> LLVM -> lli equivalence gate, to land when the parser is wired to LLVM (G6/G7-era was the placeholder; the corpus-rewrite acceptance stands in meanwhile). Plan ~282.
