# T1 and B::SoN's typing are one engine written twice

**Date:** 2026-08-29
**Status:** FINDING + proposed direction. Not yet ruled on.
**Origin:** perigrin — *"T1 and bson's typing have very similar shapes … probably
two implementations of the exact same engine, and probably we should have a
single implementation that is just duplicated between namespaces."*

## The evidence: five passes share a NAME

| chalk `IR/Analysis.pm` | perl5-son |
|---|---|
| `_propagate_computed_reprs` | `_propagate_computed_reprs` |
| `_infer_param_field_types` | `_infer_param_field_types` |
| `_infer_field_types_from_stores` | `_infer_field_types_from_stores` |
| `_stamp_field_access_reprs` | `_stamp_field_access_reprs` |
| `_stamp_method_call_reprs` | `_stamp_method_call_reprs` |
| `_seed_direct_call_arg_reprs` | `_stamp_calls_from_callees` |
| `_element_repr` | `_stamp_literal_subscripts` |
| `_join_repr` | `_stamp_merges` |
| — | **`_infer_backward`** |

Five identical names is not convergent design. It is one engine written twice.

**And the producer's is the more complete one.** `_infer_backward` has no chalk
equivalent, and it is what took wire `Unknown` 233 -> 80.

## It has already happened once, and been named

`lib/B/SoN/TypeLibrary.pm` (145 lines) is a DELIBERATE mirror of chalk's
`%BINARY_OP_SIGNATURES`, created 2026-08-29. Its header states the mechanism
that produced it:

> three partial copies of one table, none of them labelled as such

— `%OPERAND_REQUIRES` held the input half, `%SELF_TYPED_OPS` the fixed-result
cases, and a third table was about to be added. So the accidental-duplication
failure mode is documented, and the deliberate-mirror remedy is already in use
for the table. This proposal is that remedy applied to the ENGINE.

## Why a shared dependency is not available

The SoN/Chalk namespace divorce: B::SoN stands alone, and a runtime dependency
on chalk would put the producer inside the consumer. So the choice is not
"share vs duplicate" — it is **deliberate mirror vs accidental re-derivation**,
and only one of those is honest.

## What this changes about T1

T1 has been planned as something to BUILD. It is not: a working implementation
exists on the producer side. So the work is EXTRACT AND MIRROR, not author.

Consequences worth stating before anyone acts:

- **The registry question may dissolve.** Chalk's registry ruling exists so T1
  can reach more than one graph. The producer's engine already solves whatever
  it solves without one; look at how before designing chalk's.
- **`_infer_backward` is the biggest single import**, and its rule comes with
  it: *fill a hole, never preempt a source* — valid only on `PadAccess`,
  `FieldAccess`, `Parameter`. It binds chalk HARDER, since T1 can resolve
  callees the producer cannot.
- **Sizes:** chalk `Analysis.pm` 1842 lines; producer inference split across
  `B/SoN.pm` (2123) and `SoN/IR/Serialize/JSON.pm` (1334). Neither is a small
  extraction, and the shared subset is what matters, not the totals.

## What must be decided, and is NOT decided here

1. **Which side is the source of truth?** The producer's is more complete
   today. Chalk's runs against a loaded graph rather than an optree walk.
2. **What exactly is the engine?** The passes above are the candidate set; the
   boundary between "the engine" and "this side's plumbing" is unmeasured.
3. **What enforces agreement?** For `TypeLibrary` the answer is already stated:
   chalk's corpus gate runs producer output through chalk's lowering, so a
   disagreement surfaces BEHAVIOURALLY rather than silently. That is the only
   enforcement mechanism either side has, and it must cover the engine too or
   the mirror rots.
