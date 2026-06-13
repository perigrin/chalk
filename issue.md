---
title: PostfixDeref at-use aggregate pointer + symmetric reassign coverage (019eb6ff G3)
state: pending
urgency: normal
milestone: v0.1
blocked_by:
- 019eb6ff-c505-71f7-9665-5e087be277fe
created: 2026-06-13T12:49:35.616744405Z
updated: 2026-06-13T12:49:41.681992883Z
---

Low-severity coverage/path gap surfaced by the 019eb6ff per-issue review
(report: paad/code-reviews/phase1-lateral-bindings-2026-06-13-12-45-45-3de55c3a-019eb6ff-issue.md, finding G3).

019eb6ff item 3 fixed stale typed-aggregate pointers by resolving them
at-use via _container_ptr (Subscript/Length/element-store consumers). But
PostfixDeref lowering (@$ref / %$ref, _lower_array_deref / _lower_hash_deref
in Target/LLVM.pm) does NOT route through _container_ptr — it bitcasts
lower_value(...) and caches by node id. A ref-variable reassigned and then
read via postfix-deref could serve a stale typed pointer (same class as the
fix-2 bug, different code path; predates 019eb6ff, not in its claim).

Also close the symmetric behavioral coverage on the at-use path: hash
read/store after ref reassign and Length-after-reassign route through the
SAME fixed _container_ptr (structurally covered) but have no lli test.

Scope: route PostfixDeref through _container_ptr (or an equivalent
at-use resolution), add hash-reassign + Length-after-reassign + a
postfix-deref-after-reassign lli case. Pick up on a future aggregate pass.
Not gating Phase 4 (the postfix-deref-after-reassign shape does not appear
in the corpus or B::SoN's near-term lib/ targets).
