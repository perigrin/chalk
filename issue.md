---
title: "Producer: anon-ref binding through deref (my $r=[1,2,3]; $r->[0])"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-07-01T04:05:16.434346487Z
updated: 2026-07-01T04:05:16.434346487Z
---

Split from RC1 (019f1bd2). references R4/R5/R8: my $r = [1,2,3]; $r->[0] loses the container -- $r reads a bare PadAccess with no value, so Subscript.container has no ArrayRef. B::SoN FromOptree does not bind $r to Ref(ArrayRef(...)) such that the later $r->[0] deref resolves the aggregate. Producer fix: the anon-list/anon-hash (refgen -> Ref(ArrayRef/HashRef)) must bind to the pad so a deref read resolves through PadAccess -> Ref -> aggregate. Then RC1 repr-inference already handles the element type. Blocks references R4/R5/R8 (+ nested R8).
