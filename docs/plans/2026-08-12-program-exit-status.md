# A program has no return value; its contract is stdout + exit status

**Date:** 2026-08-12
**Status:** PLAN — nothing built
**Branch:** phase5-capstone (chalk) / pu (perl5-son)

## The finding

`son-corpus-wide.t` was flipped to run cases as programs (working tree, uncommitted)
and the behaviour leg held at 179 while the SHAPE leg collapsed to 22 — one
cluster of 168 cases, all `missing [<rooted wiring mismatch at return value>]`.

The cause is not 168 bad ir-blocks. It is one producer behaviour:
`_exit_record` (perl5-son `FromOptree.pm:897`) takes the Return's value from
`$sim->pop_node`, the top of the simulated stack. That is right for a sub, whose
last statement leaves its value there. A program's top level runs every statement
in VOID context, so nothing is legitimately on the stack and whatever remains is
residue from earlier statements. Measured at the program exit:

    my @a = (1,2,3); say(scalar @a);              depth=1  top=ArrayRef
    my $n=5; my $x=0; $x = 1 if $n>0; say($x);    depth=2  top=Constant(0)

`d4b`'s depth of TWO is the tell — two stale values, pure residue. The Return is
wired to `my $x = 0`'s initializer.

NOT a miscompile. `Return.control_in` IS the Print (measured: `8 Print
control_in=0`, `9 Return control_in=8`), so the effect chain is intact and the
programs print correctly. Only the Return's DATA input is wrong, which is why
behaviour passes and only shape fails.

## What perl actually does — measured, not assumed

The first fix considered was "wire Return to the last statement's value." That
models something perl does not have.

    $ perl -MO=Concise,-exec -e 'my $x = 5; $x'
    6  <0> padsv[$x:1,2] v          <-- VOID
    7  <@> leave[1 ref] vKP/REFC    <-- VOID

Perl compiles a program's trailing statement in VOID context. The value is not
merely discarded — it is never evaluated for value at all. Confirmed behaviourally:

    perl -e 'my $x = 5; $x'   exit=0
    perl -e '0'               exit=0
    perl -e 'my $x = 0; $x'   exit=0

The last value has NO effect on exit status. There is also no implicit `exit()`:
a program ends on `leave`, not an exit op. Status comes from exactly two places:

    perl -e 'die "boom\n"'    exit=255
    perl -e 'exit 7'          exit=7

So: **a program has no return value. Its observable contract is stdout plus exit
status.** Anything else Chalk emits there is an invention.

## Where Chalk already agrees

Two independent signals say the corpus has drifted to this model already:

1. Of the 191 migrated cases, **183 assert `return: Bool:1`** — "say returned
   true", a value carrying no information, sitting beside the `stdout:` line that
   does the real work. The return assertion is vestigial.
2. `ProgramRunner` — the standalone-executable contract — already compares stdout
   AND exit status and does not look at a return value at all.

And half the exit mechanism already works (measured through ProgramRunner):

    die  -> perl exit=255, chalk exit=255   PASS
    exit -> perl exit=7,   chalk cannot lower op=Call

## Scope

### S1. `exit N` lowers (perl5-son + chalk)

`exit` reaches the backend as an unlowered `Call`
(`Context.pm:571`, "cannot lower op=Call"). It is also the executable gate's ONE
remaining failure ("explicit-exit ... blocked on an unlowered `exit` Call"), so
this closes a tracked item rather than opening a new axis.

Needs: an `Exit` node (or a recognised builtin Call) that lowers to
`ret i32 N` from `@main`, and terminates the control chain. `die`'s 255 path
already exists and is the precedent to follow.

Bilateral: `exit 0` and `exit 7` must both match perl, and a program with NO exit
must still be 0.

### S2. A program's Return carries no value (perl5-son)

`_exit_record` must not take a stale stack value at a PROGRAM exit. The
`is_program` flag already exists at `FromOptree.pm:240` and is currently unused
(the comment says so). The fall-back the function already has —
`Constant(undef) :Undef` — is the honest value.

Open question for the build: whether to drain the residue (assert depth 0 and
GAP if not) or ignore it. Draining is louder; a leftover means the walk pushed
something it never consumed, which is worth knowing about. Recommend: take
Undef, and GAP if the stack is non-empty by more than a known-tolerated amount,
so residue surfaces rather than being silently dropped.

### S3. The corpus contract moves off `return:` (chalk)

Delete the vestigial `return: Bool:1` from migrated cases and the
`return %p` line from their ir-blocks. The behaviour block becomes `stdout:` +
an exit-status assertion; the shape block asserts the nodes without claiming one
of them is the program's value.

This is mostly deletion — the 183 `Bool:1` lines assert nothing. Cases with a
REAL trailing value (`return: 3`, `return: 9` — 12 of them) need their sources
migrated to `say(...)` first, which the transform already does.

Requires: `shape_subset_check` currently ROOTS its walk at the Return node
(`MdtestCorpus.pm`, `$spec_return` from `build_graph_from_ir`). A program's ir
block with no meaningful return needs a root. Decide: root at the Return anyway
(it still exists, just valueless) or root at the control chain's head. NOT yet
investigated — this is the piece most likely to be larger than it looks.

### S4. Corpus coverage for simple subroutines (chalk)

Three forms are ALREADY CORRECT and pinned by NOTHING — measured this session:

    sub f { 1 + 1 }        say f();     -> "2\n"  exit 0   PASS
    sub f { my $x = shift; $x * 2 }     -> "42\n" exit 0   PASS
    sub f { $_[0] + 1 }    say f(41);   -> "42\n" exit 0   PASS

Add these as GREEN cases.

`sub g { f() }` (a call inside a callee) GAPs on the inliner's declination
("callee has effect(s) on its control chain") — F3 territory, out of scope here,
but worth a GAP-declared case so the boundary is recorded.

## Order

1. S1 (`exit`) — self-contained, closes the executable gate's last case, and
   gives S2/S3 a working exit-status story to assert against.
2. S4 (sub corpus cases) — pure addition, no dependency, pins behaviour that is
   currently correct by accident.
3. S2 (program Return) — the producer change.
4. S3 (corpus contract) — last, because it depends on S2's shape and on
   resolving the shape-check rooting question.

Subroutine parameters (signatures, `@_`, the `$_` collision) are SPLIT OUT to
`2026-08-12-subroutine-parameters.md` — independent of this plan, and larger.

## Risks

- **S3's rooting question is unscoped.** The shape leg walks from the Return; a
  valueless Return may not give it a usable root. Measure before committing to
  an approach.
- **The migration is currently uncommitted in the working tree** (sources
  migrated, both harnesses flipped, non-vacuity check added). It should NOT land
  until S2/S3 make the shape leg green, or it lands as a regression.
- Two GAP-declared cases will remain: L3c (an Int-vs-Bool merge; see Part M) and
  D4's migrated form if it does not clear.

## What this does NOT do

Split Phi (Part M / M4) stays open. `_shortcircuit_phi_repr` and the L3c merge
both need a Phi that can carry per-arm reprs; that is independent of this plan
and is NOT unblocked by it.
