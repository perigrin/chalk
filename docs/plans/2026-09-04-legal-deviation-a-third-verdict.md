# A third verdict: DEVIATES — legal under Perl, different from `perl`

**Date:** 2026-09-04
**Status:** DESIGN. Not built. Changes the gate's central contract, so it is
argued here first.
**Trigger:** perigrin — *"We are attempting something `perl` doesn't do, static
compilation with no runtime … we can in theory deviate from 100% fidelity to
what `perl` outputs as long as it's within what Perl allows"* and *"We just
need to document the deviations and minimize them"*.

## The contract today, and what it forbids

`son-corpus-wide.t:297`:

    my $behavior_ok = !$vacuous && defined $lli && $lli eq $oracle && $status_ok;

**Exact string equality against `perl`'s stdout**, plus exit status. Two
verdicts exist in the corpus: `GREEN` (225 cases) and `GAP` (a case that does
not lower, with the reason named).

There is no vocabulary for *"this lowers, runs, and is correct Perl — but the
bytes differ from `perl`'s"*. Any such case must currently be recorded as a GAP
or made to match, and neither is honest.

## Why the latitude is real, and measured

**Perl-the-language does not specify IV vs NV.** A program cannot observe which
was used: same value, same stringification, `==` agrees. The distinction is
visible only through `B::`, which is introspection of the implementation.

**`perl` itself is not self-consistent about it**, which is the decisive
evidence that fidelity-to-`perl` is the wrong target:

    9007199254740993        prints  9007199254740993     (IV path)
    2**53 + 1               prints  9.00719925474099e+15 (NV path, ** yields NV)
    the two compare ==      yes

Same mathematical value, two different outputs from `perl`, both correct Perl.
Whichever one Chalk produced, it would match `perl` on one spelling and differ
on the other. **Byte-identity with `perl` is not a well-defined target for this
value**, so a contract demanding it is asking for something that does not
exist.

What Perl DOES guarantee (perlnumber, and `Config`): integers up to `ivsize*8`
bits are exact, and NVs carry ~15–17 significant digits. Those are the real
constraints.

## The proposal

A third `L:` verdict, alongside `GREEN` and `GAP`:

    L: DEVIATES(<reason>) expected=<what chalk prints>

Its contract is STRICTER than GREEN, not looser, and that is the point:

1. **The case must lower and run.** A DEVIATES case that stops lowering is a
   regression, exactly as a GREEN one is. It is not a GAP with better manners.
2. **The output must match the DECLARED string**, byte for byte. The gate stops
   comparing against `perl` and starts comparing against a value a human wrote
   down and justified.
3. **The reason must name the Perl-level guarantee that permits it.** "Perl
   does not specify IV vs NV" is a reason. "Close enough" is not.
4. **It counts as its own leg.** `gate-green` stays the count of cases matching
   `perl`; `deviations` is reported separately and its FLOOR RISING IS A
   REGRESSION SIGNAL, not progress. The number to drive down.

## Why a separate count rather than folding into green

Because "minimize them" needs a number. Folding deviations into `gate-green`
makes them invisible and lets them accumulate — the pattern this project has
recorded repeatedly (a GAP-declared case that silently started working; a shape
leg that passed without checking operands). A deviation that no one is counting
becomes a deviation no one removes.

So the gate line grows one field:

    TOTAL: gate-green=N behavior=N shape=N invariant=N deviations=D ...

and `D` has a ceiling in the test file the way `gate-green` has a floor.

## The first candidate, and why it is not obviously right

The 2^53 GAP (`t/corpus/mdtest/arithmetic.md`, `b7486a7f`):

    my $n = 9007199254740993; my $s = $n + 0.0; print $s;
    perl:  9007199254740993
    chalk: 9.00719925474099e+15

Under this proposal that could become
`L: DEVIATES(Perl does not specify IV vs NV; the NV rendering carries the
documented ~15 significant digits) expected=9.00719925474099e+15`.

**But that would be the wrong first use**, and recording why matters more than
the mechanism:

- The deviation is not forced. Chalk emits a float because
  `_join_repr(Int, Num)` is `Num` and `Num` means `double` — a choice made
  before any constraint is seen, not a limit of static compilation.
- `perl` produces the exact answer here, and so could Chalk. Declaring a
  deviation would freeze a defect behind a legitimising label.
- It fails test (3): the reason would describe the latitude, not why Chalk
  needs it.

A deviation is legitimate when static compilation CANNOT do what `perl` does.
It is illegitimate when Chalk simply has not yet. The 2^53 case is the second.

## Where deviations probably ARE forced

Not measured, listed as candidates for the first real use:

- **Runtime-value-dependent representation.** Perl picks IV or NV by the RESULT
  (`2^53+1 + 0.0` is IOK, `+ 0.5` is NOK — identical static types). Where the
  result is not statically known, a static compiler must pick one, and
  whichever it picks will differ from `perl` on some input.
  (`docs/plans/2026-09-04-perl-decides-repr-by-value-not-type.md`)
- **Hash iteration order**, which perl deliberately randomises per process.
- **Floating-point formatting** at the edges of `%.15g`.

The first of these is the one that motivated this document, and it is the one
where "minimize" has real content: source (a) constraints (`Divide` and
friends) reduce how often the static choice has to be a guess.

## Not established

- Whether `DEVIATES` should also assert the values compare `==` under perl
  semantics rather than only matching a declared string. That is stronger and
  probably right, but needs a numeric oracle the harness does not have.
- Whether existing GREEN cases hide deviations that happen to match on the
  probes chosen. Not audited.
- The ceiling mechanism. A floor that must not fall is well understood here; a
  ceiling that must not rise is new and has no precedent in the gate.
