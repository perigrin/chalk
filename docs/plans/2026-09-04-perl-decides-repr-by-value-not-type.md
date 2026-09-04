# Perl picks IV or NV by the RESULT VALUE, which a static pass cannot always know

**Date:** 2026-09-04
**Status:** MEASURED. Reframes the T2 narrowing work; nothing committed from
the attempt that found it.
**Producer pin:** perl5-son `b96087c`. Gate: 224 throughout.

## The measurement that changes the framing

Chasing the 2^53 GAP, I checked what perl actually does with the reproducer:

    my $n = 9007199254740993;   # B::IV
    my $s = $n + 0.0;           # B::IV  <- NOT an NV

**Perl does not promote.** Adding `0.0` does not force float arithmetic,
because perl checks whether the RESULT fits an IV. Widening the sample:

    n + 0.0    = 9007199254740993      B::IV
    n + 0.5    = 9.00719925474099e+15  B::PVNV
    2 + 1.5    = 3.5                   B::PVNV
    4 / 2      = 2                     B::PVNV     <- division always

So the rule perl follows is:

> use an IV when the RESULT is integral and fits; otherwise an NV.

That is a property of the **value**, evaluated at runtime, not a property of
the types. `n + 0.0` and `n + 0.5` have identical static types and different
representations.

## Why this invalidates the approach as designed

The narrowing design assumed the choice is decidable from static information —
three constraint sources, propagate, default. Two of the three turn out to be
approximations of a runtime test:

- **Source (b), "a fractional literal forces double"**, is WRONG as stated.
  `0.0` is a fractional literal and `n + 0.0` is an IV. The literal's spelling
  does not determine the operation's representation.
- **Source (c), "all-Int inputs prove i64"**, is SOUND but incomplete: it is a
  sufficient condition, never a necessary one, and it cannot see through the
  `Coerce[Num]` the producer inserts.

Only source (a) — a consumer stating a requirement — is a genuine static
constraint, and `Divide` is the clearest case precisely because perl's `/`
ALWAYS yields an NV regardless of value (`4 / 2` is `B::PVNV`).

## What was tried, and what each attempt taught

**Wiring `narrow_num` at `_lower_coerce`** (reverted, recorded in `c52a028d`):
narrowing one node left its consumer unchanged and emitted invalid IR —
`'%tmp_1' defined with type 'i64' but expected 'double'`.

**Substitution composition** — recursing into `Num` inputs so a decision
reaches consumers. This WORKED as a mechanism: on the real loaded graph every
node's answer became identical with the default inverted, meaning every answer
came from a rule rather than from the default. The mechanism is sound; it is
the rules it propagates that are wrong.

**`const_type` instead of the value's spelling.** The wire does carry the
distinction the value loses — `{const_type => 'number', value => '0'}` is
`0.0`, versus `{const_type => 'integer'}` for a true integer. That fixed
source (b)'s blindness and immediately exposed that source (b) is not the right
rule: it made the `Add` a `double`, which perl says it is not.

Also worth recording: my unit-test probe built `Constant` nodes without
`const_type`, which defaults to `'string'`, so it could never exercise source
(b) at all. The finding only appeared when testing against the graph loaded
from the producer. **A reconstruction of the graph is not the graph.**

## What is actually true about the 2^53 case

The GAP is real and the current output is wrong — chalk prints
`9.00719925474099e+15`, perl prints `9007199254740993`. But the fix is not
"narrow `Num` to `i64` here". It is that **`Add` over an IV and `0.0` is an IV
operation in perl**, and Chalk models it as float arithmetic because
`_join_repr(Int, Num)` is `Num` and `Num` means `double`.

Two candidate directions, neither explored:

1. **Model perl's rule.** An integral-valued arithmetic result stays an IV.
   Requires knowing the result is integral, which for constants is static
   (`9007199254740993 + 0.0` is computable at compile time) and in general is
   not.
2. **Make `Num` not mean `double`.** If a `Num`-stamped `Add` could emit
   integer arithmetic with an overflow check that promotes, this becomes
   perl's own narrow-and-promote strategy. That is the direction the
   representation-selection literature points at, and it is what
   `docs/plans/2026-09-04-t2-narrowing-the-design.md` deferred as
   promote-on-overflow.

(2) subsumes (1) and matches what perl does. It is also considerably more work
than the narrowing pass was scoped to be.

## What stands

- `observed_operand_repr` (`5d200154`) — the read-only observation channel.
  Unaffected: source (a) is the source that survives this finding.
- `narrow_num` (`a34277d5`) — correct in isolation, 7 subtests green with the
  inverted-default check. Not wired, and this document is why it should not be
  wired as-is.
- The corpus GAP (`b7486a7f`) — still the real acceptance test.

## Confirmed against the SV flags

`B::svref_2object`'s CLASS is not a reliable read -- it reports `B::IV` for one
value and `B::PVIV` for the same computation once the value has been
stringified. The FLAGS are the authority (`scratchpad/flags.pl`):

    2^53+1 + 0.0 = 9007199254740993       IOK
    2^53+1 + 0.5 = 9.00719925474099e+15   NOK
    4 / 2        = 2                      NOK
    IV_MAX + 1   = 9223372036854775808    IOK
    2 + 2.0      = 4                      IOK

Two things this settles:

- **A float-written operand does not force a float result.** `2 + 2.0` is IOK
  and `2^53+1 + 0.0` is IOK. Source (b) as designed -- "a fractional literal
  forces double" -- is refuted directly.
- **Division is the exception and is unconditional.** `4 / 2` is NOK with an
  exactly integral result, which is why source (a) via `Divide` is the one
  static constraint that survives.

`IV_MAX + 1` being IOK is worth noting separately: the value 9223372036854775808
exceeds IV_MAX, so "fits in an IV" is not the whole condition either. Perl is
using a UV there (the `SVf_IVisUV` flag distinguishes it), which this probe did
not separate out.

## Not established

- The precise condition in perl's own `pp_add`. Five data points and the flags
  are consistent with "integral result stays integral", but the source is the
  authority and was not read. The `IV_MAX + 1` case shows the boundary
  condition is subtler than "fits in an IV".
- Whether a compile-time-constant subset (both operands literal) is worth
  special-casing. It would close this specific corpus case without addressing
  the general rule, which is the kind of narrow fix that has misled this
  project before.
