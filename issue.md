---
title: "Loader: die loudly on unresolvable forward input references"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-07-03T06:23:14.047823363Z
updated: 2026-07-03T06:23:14.047823363Z
---

Found during RC2b (019f1c1e). Chalk::IR::Serialize::JSON resolves inputs single-pass; a forward index outside the sanctioned Phi-backedge deferral silently becomes undef and crashes DEEP in the backend (seen at LLVM.pm:1455 before the Graph::nodes DFS fix). A guard at the loader seam (die naming the node, slot, and index) converts future producer ordering bugs from opaque backend crashes into immediate seam errors. Small hardening, loader-only.
