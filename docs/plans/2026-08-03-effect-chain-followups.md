# Effect-chain followups (2026-08-03)

Deferred work and measured defects surfaced by the `effect-chain-fix` milestone
(plan: `2026-08-03-effect-architecture-subtraction.md`). Each entry has a
measurement behind it. Nothing here was fixed by that milestone — these are
filed so they are findable on their own rather than buried in a plan that will
be closed out.

---

# Part A — gate and harness defects

## A1: the shape leg does not check operands of CONTROL-REACHABLE nodes

Not an `If` quirk — the first framing was too narrow. `_rooted_match`
(`t/lib/Chalk/CodeGen/Harness/MdtestCorpus.pm:1146-1159`) starts at
`Return.inputs[0]` and descends **value operands only**. Any node reachable only
through control therefore gets a presence check and **never an operand check**.

Measured with direct probes against a real graph:

```
spec identical to the real graph      -> PASS
spec with a WRONG If condition        -> PASS   (should fail)
spec with a WRONG branch-arm store    -> PASS   (should fail)
```

Consequence: a corpus ir-block can encode the wrong condition or the wrong
arm-store value and stay green. Stated precisely: the shape leg does not check
the operands of control-reachable nodes, only their presence. **This is the prerequisite for the `If`/`Loop`
control normalization**, which the milestone deliberately CUT precisely because
nothing could validate it — ~120 positional construction sites across ~26 files
would have been edited under a gate blind to the change.

## A2: there is no exit-code oracle anywhere

`t/lib/Chalk/CodeGen/Harness/Mode1Runner.pm:167` turns ANY nonzero lli exit into
a skip and never compares `$?`:

```perl
return (undef, "lli exited $exit: $out", $g) if $exit != 0;
```

This is why F1's dropped `print` was invisible to the harness for so long, why
corpus T2b is GAP-declared with a prose note that the harness cannot assert an
abort, and why this milestone's die-in-arm case can only ever be a marker rather
than a regression guard. The two die miscompiles (F1, F2) had to be verified by
hand against perl, outside the harness.

Adding the comparison is small but explicitly **NOT free** — nobody has measured
how many currently-green cases would flip when a nonzero exit stops being a skip.
Measure that first.

## A3: `Assign` is not universally control-pinned by the producer

Found while defining the control-chain invariant's op set. `Assign` is pinned at
8 of 9 producer build sites; the exception is the generic list-assign fallback
(`my ($a,$b) = LIST`) at `~/dev/perl5-son/lib/SoN/FromOptree.pm:2067`, which has
no `set_control_in` call.

Zero corpus cases exercise that shape, so the new TypedInvariant control-chain
leg is green — but the gap is real, and the invariant's "Assign is always pinned"
premise is true only for corpus-exercised shapes. Adding a `my ($a,$b) = ...`
corpus case would fail the invariant leg, which would be **correct behavior**:
it is a genuinely unpinned effect.

---

# Part B — M5 seed sites (2 of 3 remaining)

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

---

# Part C — a committed plan claim that was false

`docs/plans/2026-07-23-slice-b-inliner-effect-ordering.md:259` claimed the silent
effect-drop miscompile class was CLOSED. That is true only as scoped to the
**callee**: Commit 1's guard inspects the callee's attachment paths, while the
**caller-side** path was unguarded.

F4 reproduced live on HEAD with no GAP — `sub f { print "x"; 2 } my $r = f(); 3`
printed nothing where perl prints `x`, because the producer DCE'd the unpinned
Call and chalk never saw it. The class was not closed; one side of it was.

That line has been re-scoped in place (not deleted) to say what is actually
closed, pointing at F4 and at the R1.0 Call-pin that finally closed the caller
side.

**The general lesson, worth more than the instance:** a guard that inspects one
side of a boundary does not close a class. "CLOSED" in a plan should name the
side it closes, or it will be read as the whole thing — including by the person
who wrote it.
