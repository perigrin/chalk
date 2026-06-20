---
title: "4b-4b: field writes + TARGMY result-to-pad stores in FromOptree"
state: pending
urgency: normal
milestone: v0.1
created: 2026-06-19T12:20:35.872819956Z
updated: 2026-06-20T18:18:31.891614434Z
---

4b-4 covered ARRAY/HASH element writes (R6/R7, green). Two related store-back gaps remain, both rooted in ck-stage (NOT rpeep) fusions that survive peephole suppression:

(1) FIELD writes: method inc { $n = $n + 1 } lowers to FieldAccess; Add; Return with the store-back ABSENT. The write is done via TARGMY (add op with OPpTARGET_MY, result written in-place to the pad/field slot), applied at ck_sassign time. Also hits scalar self-assign $x = $x + 1.

(2) STRING compound assign .= (from 4b-5): $s .= "b" stays multiconcat with APPEND|TARGMY even under suppression, and currently dies "No mark on mark stack" in FromOptree. Same TARGMY family. The corpus S4 contract wants Concat(pa, "b") + Assign(pa, cat) + rebind.

Fix: FromOptree must handle a TARGMY op (and multiconcat) as a store -- emit Assign over the FieldAccess/PadAccess target, record the binding so a later read sees the new value, and for multiconcat build a Concat. This unblocks the classes method-call tier (Counter::inc), references self-mutation, and strings S4.

Cross-ref: element writes done in perl5-son 2a432a2; numeric compound assign (+=) done in 4b-5.
