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
