---
title: "R3 cleanup: S2-S6 cosmetic labels + TypedInvariant coverage (deferred from R3)"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-06-10T02:20:17.535763058Z
updated: 2026-06-10T02:20:17.535763058Z
---

Deferred from R3 (node-convergence) per perigrin 2026-06-10. These are the R2-deferred Suggestions folded forward, then re-deferred from R3 because they are pure churn / forced coverage with no behavior or contract value:

- S2: stale ArrayRead/HashRead labels in _require_repr GAP messages (Target/LLVM.pm ~3408/3516) and the ~50 cosmetic .ll comment labels (; ArrayRead: / ; HashRead:) in _lower_array_read/_lower_hash_read — the canonical node is now Subscript; rename labels to match.
- S3: stale HashWrite comment at Target/LLVM.pm ~3286 (HashWrite node deleted).
- S4: the lineage comments at Target/LLVM.pm ~1288/2688/3694 (canonical form of MethodCall/New) — evergreen-comment cleanup.
- S5: TypedInvariant ArrayRef/HashRef/Assign/Call coverage. NOTE: ArrayRef/HashRef construct from HETEROGENEOUS elements (no single operand repr to require) and Assign operands are repr-polymorphic — a naive operand-repr check would be INCORRECT. The honest options are (a) a result-repr assertion, (b) Call(method) invocant=Object per-position check, or (c) document why no operand check applies. Decide deliberately; do not add a fake check.
- S6: R6/R7 references.md read-back coverage (verify the stored value reads back, beyond the partial store-text check in A19).

R3 itself shipped fully GREEN with zero new regressions; these are hygiene.
