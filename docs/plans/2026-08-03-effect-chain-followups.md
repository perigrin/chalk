# Effect-chain M5-seed followups (2026-08-03)

## Context

The M5 "trailing void statement-effect rides Return.inputs[1..]" encoding
existed to work around a pre-R1.0 producer convention: a void method call
(`$c->inc;`) was not the return value, so the loader kept it as an extra
Return input rather than demoting it to `control_in`.

perl5-son's R1.0 Call-pin (commit 40d8f8b,
"fix(fromoptree): pin control_in unconditionally so a non-void Call is never
dropped or reordered (F3/F4)") makes this encoding unproducible at the
source: every Call — void or not — now pins `control_in` unconditionally.
`SoN::FromOptree::_build_single_exit` builds `Return.inputs` as always
exactly `[value]`; see the comment there ("control_in is never a data input,
so a Return's inputs is always exactly [value] regardless of what kind of
node control is").

There were three LLVM-side sites carrying the M5
`Return.inputs[1..]`-as-extra-seed encoding. One is deleted
(`lib/Chalk/Target/LLVM.pm`'s `_process_control_chain` seed list, see commit
paired with this plan). The other two are **filed here, not touched**, per
the task's scope fence:

## Open site 1: `lib/Chalk/IR/Serialize/JSON.pm:994-1002` (`_control_chain_nodes`)

This sub is in the fenced-subs list per `t/bootstrap/mop-fence-audit.t:32` —
deleting or editing it trips the fence audit and needs its own sign-off
before touching. The seed-from-`inputs[1..]` block (lines 986-1002) is the
same M5 pattern as the deleted LLVM.pm site, now provably dead for the same
unproducible-at-source reason. Needs a decision on how to handle a fenced
sub: unfence-then-edit, or a separate fence-aware deletion path.

## Open site 2: `lib/Chalk/Target/LLVM/Context.pm:4372-4378` (trailing-effects GAP guard)

The direct-call inliner reads `$returns[0]->inputs->[-1]` as the callee's
return value (line 4371) and then, per the comment at 4385-4389, treats
`Return.inputs[1..]` as a possible trailing void statement-effect requiring
its own GAP guard. Same unproducible-at-source argument applies. Not
touched here — needs its own verification pass (the inliner path has more
surrounding logic than the LLVM.pm seed list did; Slice B's straight-line
effect chain work is layered on top of it) before deciding whether to
delete the guard outright or simplify it.

## Do not do yet

Neither open site should be treated as "obviously safe to delete" without
its own verification pass — the same rigor applied to the LLVM.pm site
(confirm the encoding is unproducible at the current producer HEAD, not
just "corpus stays green") applies to both.
