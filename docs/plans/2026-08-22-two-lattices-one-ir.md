# The producer and Chalk have DIFFERENT type lattices, bridged by a name table

**Date:** 2026-08-22
**Status:** MEASURED, not fixed. Raised by perigrin during the Parameter-node
work: *the producer should have the exact same type lattice as Chalk.*

## The divergence, measured

    CHALK only:     Bool  GlobRef  Array  Hash  Code
    PRODUCER only:  Boolean  Glob  Void  None  Unknown
    SHARED:         Scalar Undef Regex Str Num Int DualVar Ref
                    ScalarRef ArrayRef HashRef CodeRef Object List

Sources: `lib/Chalk/Grammar/Perl/TypeLibrary.pm` (%PARENT) and
`~/dev/perl5-son/lib/SoN/IR/Stamp.pm` (%PARENTS).

Two kinds of difference, and the first is worse:

**1. THE SAME TYPE UNDER TWO SPELLINGS.** `Bool` (chalk) and `Boolean`
(producer) are one type. This is already known and PAPERED OVER by a
translation table in the loader -- `Serialize/JSON.pm:30`, `Boolean => 'Bool'`,
with the comment at :514: *"says 'Boolean' where a representation says 'Bool'.
Map them ... Coerce(Boolean->Str) arrives with a repr name the backend's ...
"*. Same for `Glob`/`GlobRef`.

**2. GENUINELY ABSENT MEMBERS.** The producer has no `Array`/`Hash` -- it
carries `ArrayRef`/`HashRef` (which are REFERENCES, a different thing) plus
`List`. Chalk has no `Void`/`None`/`Unknown`.

## How it bit, concretely

Stamping a slurpy `Parameter` as `Array` in the producer dies "Unknown stamp
type: Array" -- and the translator MASKS that as a silent skip, so the entire
sub vanishes from the wire with only a stderr line. I worked around it by not
stamping and letting the loader type from the sigil.

That workaround is the wrong shape and is recorded as such: it routes around a
mismatch that should not exist. Per the memory note, "single IR" is a CONTRACT
enforced by the gate, not shared .pm files -- but a contract with a rename table
in the middle is not being enforced, it is being translated.

## What this does NOT establish

- Which direction to unify. Chalk's lattice is richer (Array/Hash/Code) and
  is what the backend needs; the producer's has the epistemic points
  (Unknown/None/Void) that this session's work made load-bearing. A merge
  probably needs both.
- Whether the `Boolean`/`Bool` table has other consumers that would break.
- Whether `List` and `Array` are meant to be the same thing.

## Why it matters beyond tidiness

`Unknown` and `None` exist ONLY producer-side, and this session established
that both are load-bearing: `Unknown` as the sound top for undetermined
inference, `None` as the bottom that makes joins work
(`join(Int, None) = Int`). Chalk's lattice has neither, which is part of why
`Unknown` is never produced on the chalk side -- there is nowhere for it to
live. The two findings are the same defect seen from opposite ends.
