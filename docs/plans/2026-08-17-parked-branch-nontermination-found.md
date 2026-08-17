# The parked branch's non-termination: a back-edge, found and named

**Date:** 2026-08-17
**Status:** DIAGNOSED. Not fixed — the branch is not being merged, so this is
the record of WHY the descent cannot be a simple recursion.
**Branch:** `~/dev/perl5-son` `modifier-effect-in-arm-parked` (`98d7d24`)
**Predecessor:** `docs/plans/2026-08-16-parked-branch-verdict.md`

## Minimal reproduction

Two seconds, simplest possible input:

    perl -Ilib -MO=SoN -e 'sub foo { 42 }'      # hangs

The `-e` program is irrelevant; the hang is in the UNFILTERED discovery pass
walking the producer's own loaded packages. Confirmed with the real filter:

| invocation | result |
|---|---|
| `-MO=SoN,package=main -e 'sub foo { 42 }'` | ok |
| `-MO=SoN,package=B::SoN -e 1` | **hangs** |

That matches `t/b-son-backend.t`'s own note — a `package=X` filter narrows
discovery enough to miss it, which is why every targeted probe and the whole
9-case shape suite looked clean.

## Where

Perl's own warning names the function:

    Deep recursion on subroutine "SoN::FromOptree::_arm_has_element_store"
      at lib/SoN/FromOptree.pm line 3861

Line 3861 is the descent the parked branch ADDED:

    if ($name eq 'and' || $name eq 'or' || $name eq 'cond_expr') {
        return 1 if _arm_has_element_store($op->other, $stop);
        next;
    }

All three predicates got the same edit (`_arm_has_element_store`,
`_arm_has_void_call`, `_arm_has_die`).

Bisected to the exact sub by watching which name the discovery walk last
reports: it gets through `B::SoN::_extract_fields` and stops. The next sub in
walk order is **`B::SoN::_initfield_default`** (`lib/B/SoN.pm:471`).

## Why — a BACK-EDGE, not a nested branch

`_initfield_default` contains no nested `if`. What it contains, at `:482`, is a
sibling-chain **loop**:

    my $k = $child->first;
    while ($$k) { $last = $k; $k = $k->sibling; }

B::Concise on that sub:

    2g  <{> enterloop(next->2s last->2x redo->2h) v
    2v  <|> and(other->2h) vK/1

The `and`'s `->other` points at **`2h`, the loop's REDO target** — backwards,
into ops the walk has already passed. A `while` loop's condition compiles to
exactly this `and`, and `->other` is the back-edge.

So the descent walks the body, reaches the `and` again, recurses into
`->other`, and re-enters the same body. Forever.

**The cycle guard cannot stop it.** `%seen` is declared `my` INSIDE
`_arm_has_element_store`, so each recursive call gets a fresh, empty one. The
guard prevents a single invocation from looping; it does nothing about
re-entry through recursion. The original non-recursive predicate was safe
precisely because one invocation plus one `%seen` was the whole walk.

## Why this matters beyond the parked branch

The fix that "obviously" makes the arm scans see nested branches — descend into
`->other` — is unsound as written, and the reason is not exotic: **`->other` is
the branch edge AND the loop back-edge, and the optree does not distinguish
them at this level.** Any descent must therefore carry the seen-set THROUGH the
recursion (pass `%seen` by reference, or hoist it to a shared closure) or the
first `while`/`until` in an arm is an infinite loop.

Note the same distinction already bit this code once, recorded at
`FromOptree.pm:~460`: "A genuine `EXPR while COND` back-edge re-enters the
CONDITION HEAD ... Require `$rhs_end` to be a TRUE back-edge (visited before
the arm)". That site solves it by consulting a `%pre_arm_visited` snapshot —
i.e. by threading visitation state across the boundary, which is exactly what
the parked descent fails to do.

## Consequence for the real work

This reinforces rather than changes the plan. The prior art's recommendation is
to DELETE these predicates and build control flow unconditionally
(`docs/research/2026-08-13-branch-merge-prior-art.md`). This is one more
measured reason: making them correct requires cross-invocation visitation
state, which is a walk-with-a-shared-seen-set — and a walk that must track what
it has visited across branch and loop edges is a graph traversal, not a
content predicate. The predicate framing is what keeps producing these.

If anyone does resurrect the descent (e.g. to salvage the parked branch's
construction code, which is measurably better than my attempt 5's), the seen
set must be threaded. That is a two-line change to the signature and a
one-line change at each call — but it must be done in all three predicates,
and the `while`-in-an-arm case must be in the test set, since no existing test
covered it.

## Method note

Perl's own "Deep recursion" warning named the function on the first
instrumented run. The bisect to the exact sub took one command — watching which
name the discovery walk last printed. Total diagnosis: about ten minutes,
after a 39-minute hang and a killed suite. Reading the warning output before
building instrumentation would have saved the first thirty of those.
