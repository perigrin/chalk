# ABOUTME: try/catch lowers to an empty main() -- every Print is dropped, silently.
# ABOUTME: The wire and the loaded graph are both correct; the loss is in backend control processing.

# D8b: try/catch emits an empty `main()`

Found 2026-09-02 by the corpus gate's new GAP-execution check (bf459ac8), which
runs a declared GAP instead of `pass()`ing it unexamined. This was the first
thing it caught and it is a LIVE SILENT MISCOMPILE.

    use feature "try";
    no warnings "experimental::try";
    my $x = 0;
    try { print "in\n"; $x = 1 } catch ($e) { $x = 2 }
    print $x, "\n";

    perl:   in
            1
    chalk:  (nothing), exit 0

Not a refusal. The module lowers cleanly, `lli` exits 0, and the program prints
nothing. Measured on pinned producer c45c9b7.

**BOTH prints are dropped**, not only the try body's: the emitted module
contains ZERO `puts`/`printf`/`write` calls and `@main()` is empty.

## Pre-existing, not a regression from this session

Verified by running the same case against session-start HEAD `a06e4ff9` in a
detached `git archive` tree: identical empty output. The GAP declaration was
hiding it, which is exactly the failure mode the gate change was written to
end.

## The wire is correct

Traced node by node from the producer JSON, with consumers resolved:

    #0  Start     ctl=None            consumed_by=[ctl<-Print#6, Region#8]
    #5  Constant  ctl=None            consumed_by=[Print#6]
    #6  Print     ctl=0    <- [#5]    consumed_by=[ctl<-Print#7]     <- try body
    #7  Print     ctl=6    <- [#3,#4] consumed_by=[Region#8]         <- print $x
    #8  Region    ctl=None <- [#7,#0] consumed_by=[ctl<-Return#9]
    #9  Return    ctl=8    <- [#1]

`Print#6` (the try body's `print "in\n"`) sits on the control chain at `ctl=0`,
and `Print#7` chains off it at `ctl=6`. The producer expressed the ordering
correctly.

## The loaded graph keeps the chain

    Region inputs:  Print (ctl=Print), Start (ctl=undef)
    Print#7->control_in  IS a Print

So the loader did not drop the edge either. Note `$g->nodes` reports only ONE
Print -- that is expected and not the bug: `nodes()` walks inputs from the
returns, and `Print#6` is reachable only via `control_in`, which is precisely
what `_control_chain_nodes` exists to augment.

## So the loss is in the backend

`Chalk::Target::LLVM` receives a graph whose control chain reaches both Prints
and emits neither. The case's own prose (control-flow.md D8b) says the backend
"refuses loudly -- measured directly against `Chalk::Target::LLVM->lower`",
and that is no longer true; something made it lower, and lowering here means
dropping the effects.

The prose also names the mechanism to check first: a `Region` built by a
try/catch merge is not built by `_process_if_node` / `_process_loop_node`, so
whatever bookkeeping those set up is absent. The old behaviour was a loud
refusal when a `Phi` was read cold.

ON THE WIRE both Phis (`#11`, `#12`) are consumed by nothing -- measured. That
is suggestive of why nothing refuses any more (a Phi nobody reads cannot be
read cold) but it is NOT established as the cause: an unconsumed Phi is what
the producer emits for a merge whose value is discarded, and `$x` IS read here.
The next step is to find which backend path was supposed to walk this Region
and does not, rather than to reason further from the Phi.

NOT EVIDENCE, recorded so it is not mistaken for some: `$g->nodes` lists zero
Phis in the loaded graph. That is just `nodes()` walking inputs from the
returns, the same reason it lists only one Print, and says nothing about
whether the backend can see them.

## Why it stayed hidden

The case was declared `L: GAP`, and the gate `pass()`ed a declared GAP without
running its source. A GAP declaration is a CLAIM that something does not
compile; nothing checked the claim. When the refusal it described stopped
happening, the declaration silently became a lie that read as coverage.

That blind spot is now closed (bf459ac8). This is the first thing it found.

---

# RESOLVED 2026-09-02 (6571632c)

`lli` now prints `in` then `1`, matching perl. Corpus gate 214 -> 215, every
leg up, nothing broken.

## The cause, confirmed

Two defects, in the place this doc predicted ("the loss is in the backend's
control processing"):

1. `_process_control_chain`'s Region arm asks a Region for its `head` -- the
   owning If/Loop -- so it can process the head instead. A try/catch Region has
   NO head, because the desugaring builds a shared-control merge with no
   runtime test for an If to be built from. The arm fell to its else, pushed
   the bare Region, and `last`: every effect behind it on the chain was
   abandoned.

2. `process_control_node` handles If, Loop, statement-nodes and Unwind. A
   Region matches none of them and falls off the end of the sub, so even the
   pushed node emitted nothing. PUSHING A NODE THAT EMITS NOTHING is what made
   this look handled while dropping everything.

A headless Region now walks its ARMS (its inputs are the arms' tails) instead
of ending the chain. All arms, not just the first -- taking one would have
fixed the reported case and left its bilateral partner broken.

## What this doc got right, and one thing it flagged as not-evidence

RIGHT: the wire is correct (Print#6 at ctl=0, Print#7 chained at ctl=6), the
loader keeps the chain, and the loss is downstream of both. Verified before
blaming, in a detached archive tree.

The unconsumed Phis were recorded here as SUGGESTIVE BUT NOT ESTABLISHED, and
that caution was right: they are a symptom of the same desugaring, not the
cause. The cause is the head lookup. Had they been written up as the diagnosis,
the fix would have been aimed at Phi bookkeeping and missed.

## The GAP declaration is retired

D8b was `L: GAP` with prose asserting the backend "refuses loudly". It stopped
refusing at some point and nothing noticed, because the gate `pass()`ed a
declared GAP without running it. The GAP-execution check (bf459ac8) is what
surfaced this, and on this fix it reported the case as "now LOWERS AND MATCHES
perl -- promote it to a real case". Promoted: the ir block now describes the
headless-Region shape.

## Still open, and NOT chalk's

A `die` inside a try is dropped SILENTLY by the producer, along with the entire
catch body. Measured on the wire: no Unwind, no "boom" constant, no "caught"
constant, and no warning. Reported to perl5-son. Recorded in
`t/bootstrap/ir/a-headless-region-does-not-end-the-chain.t` as a KNOWN WRONG
ANSWER via `isnt` rather than skipped, so it fails the day the producer emits
the Unwind.
