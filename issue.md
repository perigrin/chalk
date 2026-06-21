---
title: "multiconcat decoder: dynamic + multi-part string concatenation/interpolation"
state: pending
urgency: normal
milestone: v0.1
created: 2026-06-21T03:28:20.024099693Z
updated: 2026-06-21T03:28:20.024099693Z
---

4b-4b handled the COMMON .= case: an APPEND multiconcat with nargs==0 (all-const parts), modeled as Concat($s, lit) + rebind. The general multiconcat decoder remains: dynamic parts ($s .= $t, nargs>0) interleave const segments (in aux_list) with dynamic operands (on the stack) in a position-encoded order, plus the non-APPEND interpolation form (qq{$a$b$c} = multiconcat building a fresh Str). multiconcat is a UNOP_AUX; aux_list = [nargs, seg0, len0, seg1, len1, ...] with the dynamic args spliced between segments. This is the concat analog of the multideref decoder (which suppression let us avoid -- but multiconcat is ck-stage, NOT removed by suppression, so there is no suppression escape). Unblocks strings interpolation + variable .=. Cross-ref: const-append .= done in 4b-4b.
