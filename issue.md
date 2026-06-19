---
title: "4b-3a: B::SoN stamps only leaf Constants, not computed nodes (Add/etc.)"
state: in-progress
urgency: normal
milestone: v0.1
created: 2026-06-18T20:15:19.434472525Z
updated: 2026-06-19T01:12:07.643707576Z
sessions:
- start_sha: 4579e823078d50b5393a5c1e49c50804bff22559
  end_sha: ""
  commits: 0
  started_at: 2026-06-19T01:12:07.643707576Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-06-19T01:12:07.643707576Z
---

Localized by the 4b-3 e2e runner (t/bootstrap/corpus/son-e2e.t). A non-folded arithmetic result (e.g. my $x=1; my $y=2; $x+$y) produces an Add node, but B::SoN stamps only leaf Constants. Chalk runs no representation inference on loaded graphs, so the Add reaches the LLVM backend with no representation and GAPs (_require_repr, LLVM.pm). Fix options: (a) B::SoN stamps computed nodes via its Stamp lattice join; (b) Chalk runs a representation-inference pass on loaded B::SoN graphs. Blocks the multi-node-arithmetic part of the producible-now slice.
