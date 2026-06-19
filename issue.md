---
title: "4b-4b: field writes + TARGMY result-to-pad stores in FromOptree"
state: pending
urgency: normal
milestone: v0.1
created: 2026-06-19T12:20:35.872819956Z
updated: 2026-06-19T12:20:35.872819956Z
---

4b-4 covered ARRAY/HASH element writes (R6/R7, green). FIELD writes remain: method inc { $n = $n + 1 } lowers to FieldAccess; Add; Return with the store-back ABSENT. Root cause: the write is done via TARGMY (add op with OPpTARGET_MY, result written in-place to the pad/field slot) which is applied at ck_sassign time, NOT rpeep -- so peephole suppression (4b-4 Commit A) does NOT remove it. FromOptree must handle a TARGMY op as a store: emit Assign over the FieldAccess/PadAccess target and record the binding so a later read sees the new value. This also fixes scalar self-assign ($x = $x + 1) which has the same TARGMY shape. Unblocks the classes method-call tier (4a Counter::inc probe) and references self-mutation. Cross-ref: 4b-4 element-writes done in perl5-son commit 2a432a2.
