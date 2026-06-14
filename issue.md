---
title: PostfixDeref at-use aggregate pointer + symmetric reassign coverage (019eb6ff G3)
state: pending
urgency: normal
milestone: v0.1
blocked_by:
- 019eb6ff-c505-71f7-9665-5e087be277fe
created: 2026-06-13T12:49:35.616744405Z
updated: 2026-06-14T03:57:50.892210785Z
---

UPDATE 2026-06-14 (whole-branch agentic review, report:
paad/code-reviews/phase1-lateral-bindings-2026-06-13-13-47-41-aee6d5c8-whole-branch.md):
the CORRECTNESS worry that opened this issue is DISPROVED. PostfixDeref is
in %PURE_DESCEND_OPS, so _reads_mutable_location descends through @$ref/%$ref
to the PadAccess and the deref re-lowers with the fresh ref after a reassign.
Probe-confirmed twice (review + re-run): `my $r=[1,2]; @$r; $r=[9,9,9]; @$r`
gives the NEW array (Int:5), not a stale pointer. _lower_array_deref/
_lower_hash_deref do NOT need to route through _container_ptr — the cache
bypass already covers them.

So the original "route PostfixDeref through _container_ptr" task is DROPPED
(no bug to fix). What remains is OPTIONAL coverage-locking, low priority:

1. Behavioral lli tests that lock the at-use path the 019eb6ff fix covers
   structurally but doesn't test directly: hash read/store after ref
   reassign, Length-after-reassign, postfix-deref-after-reassign. All route
   through the now-fixed _container_ptr / the cache bypass; these would
   regression-guard the fix, not find a bug.
2. STATE-F5 (whole-branch review suggestion): Assign(Array-lvalue) with an
   unboxed container repr='Array' GEPs a value that lowered to i8* — a late
   lli type error reachable only via a malformed repr combination the corpus
   never produces. A representation-discipline assertion ('Array' container
   => value must be a %Array* producer) would convert the late type error
   into an early GAP. Loud not silent, pre-existing.

Pick up on a future aggregate/representation pass. Not gating anything.
