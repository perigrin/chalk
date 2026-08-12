# Subroutine parameters are not modelled: `@_` is fictional and `$_` collides with it

**Date:** 2026-08-12
**Status:** PLAN — nothing built
**Split from:** `2026-08-12-program-exit-status.md` (which now covers exit status only)
**Blocks:** self-hosting — `lib/` is written in signature style

## Summary

Three defects, one root: Chalk has no model of a subroutine's parameters.
Arity is INFERRED by searching the callee body for `shift @_`; `@_` itself is a
fiction (a `StashAccess` of a package variable nothing ever writes); and that
node cannot tell `$_` from `@_`, so the two hash-cons into one.

## P0. The governing principle: everything is SSA

There is no argument for why any of this should not be SSA, and the defects
below are all the same failure to apply it: **a store is a definition**.

Where that has been applied it worked. Where it has not, the same class of bug
keeps surfacing:

| site | what it does instead | symptom |
|---|---|---|
| package scalars | `StashAccess` is in `%MUTABLE_READ_OPS` — "re-lowers at every use and observes the post-store value", i.e. a memory load | per-repr slot arms (Int/Str/Num) and a GAP for anything else |
| `@_` | a `StashAccess` of a variable NOTHING writes | arity inferred by pattern-matching `shift` sites |
| aggregate element stores | element repr comes from LITERAL INITIALIZERS only | a type-changing store is invisible; Str/Num stores GAP (Part K) |
| `$_` vs `@_` | one node names a LOCATION, not a definition | two distinct values hash-cons together |

Each row is a value being modelled as a location. SSA says the value flowing out
of a store is a new definition with its own representation, which is exactly the
fact every one of these paths is missing.

The reference axis is the only real exception, and it is narrower than it looks:
a variable that is REFERENCED needs storage SOMEWHERE, but that governs where
the bytes live, not whether the value is a definition. `%Slot` is a storage
format; the value stored into it can still be SSA.

So the statement of work is not "model parameters as declared data" — it is
**parameters are definitions like any other, and `@_` is a value, not a
location.**

## P1. SIGNATURE subs must work — `sub f ($x) { ... }`

NOT optional and NOT the same as the `@_` forms. This is the idiomatic 5.42
spelling, it is what this project's own style mandates, and `lib/` is written in
it — so self-hosting needs it.

All three signature shapes GAP today with the SAME message as the list-assign
form, which is what makes the cause easy to misread:

    sub f ($x) { $x * 2 }                            GAP
    sub add ($x, $y) { $x + $y }                     GAP
    sub greet ($n, $g = "hello") { "$g, $n" }        GAP
    -> "callee reads 0 positional argument(s) via `shift @_` but the call passes N"

The cause is NOT missing producer support. Measured, the producer ALREADY
handles the signature ops — `FromOptree.pm:1846` binds `argelem` to a
`PadAccess` on the pad slot. The optrees differ entirely from the `@_` forms:

    signature      argcheck(1,0) ; argelem(0)[$x] ; padsv[$x] ...
    list-assign    padrange[$x]/LVINTRO ; aassign ; padsv[$x] ...
    shift (works)  shift ; padsv_store[$x]/LVINTRO ; padsv[$x] ...

The GAP is in CHALK's inliner: `_collect_positional_arg_reads`
(`Context.pm:~4684`) counts a callee's parameters by finding `shift @_` reads. A
signature sub has none — its parameters arrive via `argelem` — so the collector
counts 0, the arity check compares 0 against N, and it refuses.

**The fix is NOT "recognise `argelem` too".** Adding a second pattern to the
matcher keeps the broken shape. The real defect is that arity is being INFERRED
FROM USES rather than read from the DECLARATION.

`shift @_` is one idiom for reading a parameter, and a search for it both
under- and over-counts. It misses `sub f ($x)`, `$_[0]`, `my ($x,$y) = @_`, a
conditional shift, `@_` passed onward, `scalar @_`; and a `shift` inside a loop
is one syntactic site but N runtime reads. Any body past straight-line code
breaks the inference. That is also why the GAP message misleads: "callee reads 0
positional argument(s) via `shift @_`" reports what the collector SEARCHED FOR,
not what the sub IS — the same "message names a capability, cause is elsewhere"
trap D4 cost us.

Perl hands us the declaration directly. From the measured optree:

    2  <+> argcheck(1,0) v          <-- 1 required, 0 optional: THE ARITY
    4  <+> argelem(0)[$x:4,5] v/SV  <-- parameter 0 binds to $x: THE INDEX

That is the L1 boundary working as intended — the optree says what the IR is.
The producer currently DISCARDS both. Measured, `main::f` for `sub f ($x)` is:

    0 Start
    1 PadAccess <- [] targ=1,varname=$x     <-- no param marking, no index
    2 Constant(2)
    3 Multiply <- [1 2]
    4 Return <- [3]

Nothing distinguishes that `PadAccess` from an ordinary lexical read. Meanwhile
the CALLER's Call node already carries `param_names=ARRAY(...)` — so the call
site knows about parameters while the callee does not record which node is which.

So S5 is: **carry the declared parameter list on the graph** — the producer
records `argcheck`'s arity and each `argelem`'s index (a `Param(index, name)`
node, or a parameter list on the graph that PadAccess nodes reference) — and the
inliner READS it instead of searching the body. `shift @_` then becomes what it
always was: one lowering of a parameter read, not the definition of arity. The
subs that work today keep working, bound against a declared list rather than
being the source of truth for it.

This also removes a whole class of future false GAPs, since every other
parameter-reading idiom stops needing its own pattern in the collector.

#### S5a. There is no `@_`, and that is why arity is inferred at all

Arity "should" be the size of `@_` at entersub. Measured, **`@_` does not
exist**. `_args_source` (`FromOptree.pm:4261`) models it as:

    StashAccess(stash_name => 'main', var_name => '_')

— a symbol-table read of `@main::_` that NOTHING EVER WRITES. There is no
argument array, no binding at entersub, no aliasing. The caller's
`_handle_entersub` does `pop_to_mark` and holds the real argument nodes; the
callee reads a placeholder; the ONLY thing joining them is the inliner
pattern-matching `shift @_` reads back onto the caller's args.

So arity-by-searching-for-`shift` is not a heuristic layered over a real `@_` —
it is the entire caller/callee bridge. That is why signature subs GAP (no
`shift`, so no bridge) and why `sub g { f() }` GAPs (no inline substitution).

#### S5b. `$_` and `@_` are THE SAME NODE — sigil is not modelled

`StashAccess` carries `stash_name` and `var_name` only. No sigil. So `$_` and
`@_` are both `(main, '_')`, hash-cons to ONE node, and any sub that touches
both conflates them. Measured on `sub f { my $n = shift; return $n + length($_) }`:

    == main::f
      1 StashAccess stash_name=main,var_name=_      <-- ONE node
      2 Call shift <- [1]                            <-- shift @_
      3 Length <- [1]                                <-- length($_)  SAME NODE
      4 Add <- [2 3]

`length($_)` is reading the ARGUMENT ARRAY. Perl says 4; chalk currently GAPs
("callee accesses @_ as an aggregate") — but for the WRONG REASON: the guard
fires because it thinks `length($_)` is an aggregate access on `@_`. The GAP is
accidental cover for a conflation, not a diagnosis of it. Remove that guard for
any other reason and this becomes a silent miscompile.

(Also visible above: `$_ = "abc"` in `__PROGRAM__` produced no store at all.)

#### S5c. This is a package-SSA leftover, in a second location

Package-SSA narrowed `StashAccess` to ONE role — "the ENTRY DEFINITION, naming a
variable's incoming value before any assignment in this unit"
(`2026-08-03-effect-chain-followups.md:754`). Reads and writes go through SSA
bindings.

`_args_source` mints a FRESH `StashAccess` per bare `shift`, which is neither an
entry definition nor SSA-bound — the old role surviving in one spot. That plan's
own text records fixing the identical bug elsewhere: "the implicit `$_` match
subject, which built a fresh StashAccess and so bypassed the binding". `@_` is
the same bug in a second location, missed because it was not recognised as the
same class of thing.

Consequence for S5: modelling parameters as declared data is not just the
cleaner design, it is the only way to stop minting unbound `StashAccess` nodes
for `@_`. Sigil-tagging `StashAccess` would fix the `$_`/`@_` collision but
leave the fictional-`@_` problem intact.

Bilateral coverage: one-parameter, two-parameter (so positional ORDER is
tested — a one-arg test passes even if the binding is index-blind), and a
defaulted parameter called BOTH with and without the argument. A default that is
never exercised on the defaulting path pins nothing.

`sub f { my ($x) = @_; ... }` (list-assign from `@_`) is a DIFFERENT mechanism
— `aassign` from the args array — and stays GAP-declared as corpus F7. Record
its measured message; do not fold it into S5.

