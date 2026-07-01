---
title: "RC1: repr-inference for Subscript/RegexMatch/field nodes (Phase 4, ~15 cases)"
state: pending
urgency: normal
milestone: codegen-harness
created: 2026-07-01T03:56:57.313868946Z
updated: 2026-07-01T03:56:57.313868946Z
---

Phase 4 corpus-wide root cause RC1 (highest leverage, ~15 cases). See docs/plans/2026-07-01-phase4-corpus-wide-status.md.

"reached LLVM backend with NO representation (undef)" -- a repr-inference gap on non-Constant nodes the 4c-1b repr machinery does not yet seed:
- Subscript.container (7): references R2/R3/R4/R5/R8/R9/R10 -- an aggregate read whose container node carries no repr.
- RegexMatch (4): regex R1/R4/R5.
- MOP::Method body root + Call(method) (5): classes field-basic/field-attrs/class-isa/adjust/method-call-val + variables A5.

The loader has _stamp_field_access_reprs + _propagate_computed_reprs (4c-1b, Serialize/JSON) but they do not cover Subscript containers (ArrayRef/HashRef/aggregate reads), RegexMatch, or type-source-less fields. A repr-inference pass that seeds container/aggregate/regex reprs (from stamps + the ArrayRef/HashRef producer type) and propagates through Subscript/Length closes most of RC1.

SUBSUMES the narrow already-filed issue 019f0597 (field type inference: method returning a field) -- that is the field slice of RC1. Closing RC1 unblocks most of references + regex + the rest of classes.
