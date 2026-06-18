---
title: "4b-3a: B::SoN stamps only leaf Constants, not computed nodes (Add/etc.)"
state: pending
urgency: normal
milestone: v0.1
created: 2026-06-18T20:15:19.434472525Z
updated: 2026-06-18T20:15:19.434472525Z
---

Localized by the 4b-3 e2e runner (t/bootstrap/corpus/son-e2e.t). A non-folded arithmetic result (e.g. my $x=1; my $y=2; $x+$y) produces an Add node, but B::SoN stamps only leaf Constants. Chalk runs no representation inference on loaded graphs, so the Add reaches the LLVM backend with no representation and GAPs (_require_repr, LLVM.pm). Fix options: (a) B::SoN stamps computed nodes via its Stamp lattice join; (b) Chalk runs a representation-inference pass on loaded B::SoN graphs. Blocks the multi-node-arithmetic part of the producible-now slice.
