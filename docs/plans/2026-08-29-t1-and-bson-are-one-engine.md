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

## RULED 2026-08-29 (perigrin): the producer's implementation IS the source

> For Chalk the source of truth is to take the Producer's implementation and
> modify it to run against a loaded graph.

So chalk does not author T1 and does not import `_infer_backward` into
`Analysis.pm`. It takes the producer's engine and adapts it. That is the
opposite direction from the one I had assumed.

**And the adaptation is smaller than the ruling's wording implies, because the
engine is ALREADY graph-based.** Measured 2026-08-29:

| pass | lines | optree references |
|---|---|---|
| `_stamp_field_reads` | 25 | 0 |
| `_stamp_reader_accessors` | 35 | 0 |
| `_stamp_calls_from_callees` | 19 | 0 |
| `_stamp_literal_subscripts` | 17 | 0 |
| `_stamp_merges` | 40 | 0 |
| `_stamp_derived` | 17 | 0 |
| `_infer_backward` | 69 | 0 (the one grep hit is the `B::SoN::TypeLibrary::` package prefix) |
| **total** | **222** | **0** |

`_infer_backward($graphs)` takes a graph set and iterates `$graph->nodes->@*`.
There is no `B::` optree access anywhere in the engine. So "modify it to run
against a loaded graph" is not a rewrite from optree-walking to graph-walking —
it is a VOCABULARY translation (`SoN::IR::Value` -> `Chalk::IR::Value`, the
stamp accessor) plus an entry point.

222 lines against chalk `Analysis.pm`'s 1842 is also the shape of the answer to
question 2 below: the ENGINE is small, and most of `Analysis.pm` is this side's
plumbing.

## What must be decided, and is NOT decided here
2. **What exactly is the engine?** The seven passes measured above (222 lines)
   are the strong candidate. What is NOT yet established is which parts of
   chalk's 1842-line `Analysis.pm` the mirror REPLACES versus which are
   genuinely chalk-side plumbing that must survive.
3. **What enforces agreement?** For `TypeLibrary` the answer is already stated:
   chalk's corpus gate runs producer output through chalk's lowering, so a
   disagreement surfaces BEHAVIOURALLY rather than silently. That is the only
   enforcement mechanism either side has, and it must cover the engine too or
   the mirror rots.

---

## CORRECTION 2026-08-29: 222 was an undercount, and the duplication is worse
## than "one engine written twice"

**The 222-line figure counts only `B/SoN.pm`.** The producer has FIVE more live
inference passes in `SoN/IR/Serialize/JSON.pm` (each with 2 references —
definition plus call, so none is dead):

| pass | lines |
|---|---|
| `_propagate_computed_reprs` | 89 |
| `_stamp_method_call_reprs` | 60 |
| `_stamp_field_access_reprs` | 51 |
| `_infer_field_types_from_stores` | 42 |
| `_infer_param_field_types` | 14 |
| **subtotal** | **256** |

So the engine is **~478 lines**, not 222. I flagged this as a risk to the
reviewer before checking it; it is real, and it roughly doubles Path A's port.

**And the location is the finding.** Those five live in the producer's
`SoN/IR/Serialize/JSON.pm`, which has its own `from_json` (`:663`) and calls
inference from inside it (`:717`). That is the SAME FUSION chalk has —
inference inside deserialization, in a file of the same name, in both repos.

This is not two implementations of one engine. It is **one architectural defect
duplicated on both sides**: the loader doing inference. Chalk's Phase 5 exists
to split that on the chalk side (`JSON.pm:707`); nothing has proposed splitting
it on the producer side, and the ruling to adopt the producer's implementation
would import the fusion along with the engine unless the port separates them.

Which sharpens the open question about what "the engine" is: the passes are
identifiable, but on BOTH sides they are entangled with a loader, and the port
has to disentangle rather than copy.
