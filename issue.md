---
title: "Cache/identity family follow-ups: RegexMatch identity, loop-exit phi wiring, aggregate-table keying, collector drift"
state: done
urgency: normal
milestone: v0.1
blocked_by:
- 019eb316-0c85-7a68-87fc-f0c1cd221b5a
blocks:
- 019eaa51-bcfe-76b6-a02d-a23a65bd7498
- 019ec107-d180-7a26-93f8-12feeeffb6a1
created: 2026-06-11T14:04:35.973450184Z
updated: 2026-06-13T12:49:51.806916571Z
sessions:
- start_sha: d8406a4d7bfec4174defdb278ad7f22704105098
  end_sha: aee6d5c89ba11a0ea057fb8ca1c25c756d717b90
  commits: 8
  started_at: 2026-06-12T04:39:02.650467055Z
  ended_at: 2026-06-13T12:49:51.806916571Z
transitions:
- state: in-progress
  actor: human:git-zhi
  timestamp: 2026-06-12T04:39:02.650467055Z
- state: done
  actor: human:git-zhi
  timestamp: 2026-06-13T12:49:51.806916571Z
observed_paths:
- lib/Chalk/IR/NodeFactory.pm
- lib/Chalk/IR/Schedule/Elaborate.pm
- lib/Chalk/Target/LLVM.pm
- paad/code-reviews/phase1-lateral-bindings-2026-06-13-12-45-45-3de55c3a-019eb6ff-issue.md
- t/bootstrap/ir/llvm-aggregate-table-keying.t
- t/bootstrap/ir/llvm-collector-statement-effects.t
- t/bootstrap/ir/llvm-inherited-adjust.t
- t/bootstrap/ir/llvm-literal-alloc-identity.t
- t/bootstrap/ir/llvm-loop-exit-region-phi.t
- t/bootstrap/ir/llvm-regex-match-identity.t
- t/bootstrap/ir/statement-effect-identity.t
---

Pre-existing same-family defects surfaced by the 019eb316 per-issue agentic review
(paad/code-reviews/phase1-lateral-bindings-2026-06-11-13-52-37-d4823444-019eb316-issue.md).
All are the value-cache/statement-identity family formalized by 019eb316's
%STATEMENT_EFFECT_OPS table and %MUTABLE_READ_OPS predicate, but outside its
four probe-proven scopes. None are regressions from that issue.

Punch list (severity order):

1. RegexMatch/Match are in NEITHER the per-call identity table NOR the
   staleness predicate (LIVE-REPRODUCED: `my $s="b"; my $y=($s=~/b/);
   $s="x"; my $z=($s=~/b/); return $z` -> Bool:1 vs perl false). Two
   identical matches hash-cons to one node; the second cache-serves the
   first's i1 and _regex_captures holds one offsets record for both program
   points (stale $1). RegexSubst got per-call identity; its read sibling
   did not. Consistent fix: per-call identity for RegexMatch/Match (NOT
   re-lowering -- that re-runs the matcher per consumption). Parse-path
   blast radius: the Actions Block fixup shares the table, so RegexMatch
   statements would become control-threaded; needs its own RED tests over
   the regex corpus. Audit BacktickExpr (qx) at the same time.

2. Loop-exit _wire_region_phis (LLVM.pm ~2970) got neither the Family-B nor
   Family-C treatment: it lowers exit-phi arm values in the EXIT block
   itself ("should already be in cache" no longer holds post-B) -> phis not
   grouped at block top / non-predecessor labels. Latent: parser graphs
   wire exit-phi arms to cached Assign/VarDecl/Phi nodes; cfg-loop tests
   are a known baseline. Fix shares the two-pass _lower_arm_in_tail shape
   landed for the if/else path (623be688).

3. _arr_table/_hash_table keyed by node id defeat the mutable-read
   re-lowering for aggregate CONTAINERS (LLVM.pm ~2211/3568/3668/3769):
   populated under `unless exists`, never invalidated, and at two sites
   PREFERRED over the freshly re-lowered cache ref. Failure modes:
   ref-var reassign serves the old array's bitcast (silent wrong-array
   read); container first consumed inside one branch arm serves a
   non-dominating bitcast in the other (verifier error). Fix: key by the
   container's current SSA ref, or refresh when
   _reads_mutable_location(container).

4. ArrayRef/HashRef literals content-hash-cons: `my @a=(1,2); my @b=(1,2);`
   share ONE malloc -- mutations alias across "distinct" literals.
   Allocation is an effect (the Call(new) precedent); candidates for the
   per-call table.

5. Backend collector op-list drift vs the canonical table:
   process_control_node (no RegexSubst/TryCatch -> statement-position s///
   in the top-level chain emits NOTHING), _collect_body_recursive (no Call
   -> statement-position method call inside an if-branch is dropped),
   Schedule/Elaborate.pm _collect_chain_recursive (same). These should read
   %STATEMENT_EFFECT_OPS (plus VarDecl/If/Loop) or die loudly on table ops
   they cannot lower.

6. Lower-confidence latents: inherited ADJUST blocks never run (inheritance
   flatten copies methods, not adjusts; no GAP die); _lower_arm_in_tail's
   var_table snapshot restore discards first-lowering VarDecl entries while
   cache entries persist (coherence split; loud failure if hit);
   _find_phi_backedge_value lowering a pure-over-PadAccess backedge against
   post-body state would double-apply (parser graphs wire Assign nodes, so
   latent); VarDecl/ListAssign per-call branches live outside the table and
   ListAssign is not control-threaded by the Block fixup.
