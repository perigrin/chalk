# The arrow map is not a functor on the subtype poset

**Date:** 2026-09-04
**Status:** MEASURED. This CORRECTS the design in
`2026-09-04-t2-is-a-functor-objects-and-arrows.md`, which is right that arrows
must be mapped and wrong about which category they live in.
**Producer pin:** perl5-son `b96087c`.

## The correction

The functor doc says:

> The source category's arrows are the subtype edges in `%PARENT`.

and lists five of them. It then proposes a table mapping each subtype edge to
the LLVM operation realising it, with `_emit_coercion`'s 19 call sites becoming
lookups in that table.

**Measured against `_emit_coercion`'s actual branches, that table covers 7 of
24 arrows.** The classification, by `TypeLibrary::is_subtype`:

| class | count | pairs |
|---|---|---|
| **upcast** (`f <: t`) | 7 | `Int→Num`, `Int→Str`, `Num→Str`, `Int→Scalar`, `Str→Scalar`, `Undef→Scalar`, `Boolean→Scalar` |
| **downcast** (`t <: f`) | 7 | `Num→Int`, `Str→Num`, `Str→Int`, `Scalar→Int`, `Scalar→Str`, `Scalar→Num`, `Scalar→Boolean` |
| **sideways** (unrelated) | 10 | `Int→Boolean`, `Num→Boolean`, `Boolean→Num`, `Boolean→Int`, `Undef→Int`, `Undef→Num`, `Undef→Boolean`, `Str→Boolean`, `Boolean→Str`, `Undef→Str` |

Seventeen of twenty-four arrows **do not exist in the source category at all**.
A functor cannot map an arrow that is not there. The subtype poset is not the
domain.

Reproduce: `scratchpad/arrows.pl` (classification), `scratchpad/coverage.pl`
(completeness).

## What the domain actually is

The coercion table is a category in its own right — objects are the six
lowerable Chalk types, arrows are *conversions*, and the subtype poset embeds
into it as the sub-category of total, information-preserving arrows. The three
classes are not stylistic variants; they have different algebraic character:

- **upcast** — total, and on the `Int <: Num <: Str` spine, injective.
  EXPECTED to compose; measured below, that expectation rests on a single
  tested triple and that triple FAILS.
- **downcast** — **partial or lossy**. `Str→Int` on `"3.9x"` is not the inverse
  of anything. It can only be a section of the corresponding upcast, never an
  isomorphism.
- **sideways** — goes through a meet or a join. `Int→Boolean` is truthiness;
  `Undef→Int` is the zero of the target. Neither factors through a subtype edge.

This is why composition fails in the recorded way rather than randomly.
`coercion-composition-law.t`'s three kinds line up exactly with it:

1. *lossy by design* — a route through `Boolean`, i.e. through a **sideways**
   arrow into a smaller object. Failure is correct.
2. *the precision miscompile* — `Int→Num→Str`, all **upcasts**, and this one
   SHOULD compose. It is the only kind where composition failure is a defect,
   and the test already argues it is an OBJECT-map defect (`Num ↦ double`), not
   an arrow-map one.
3. *the inversion* — `Undef→Boolean`, **sideways**, where the composed route is
   right and the direct arm wrong.

So the law worth asserting is not "all arrows compose". The candidate is:

> **Composition holds on the upcast sub-category.**

**Measured against the recorded verdicts, this is TRUE, EXACTLY ONE-SIDED, AND
NEARLY VACUOUS** (`scratchpad/lawcheck.pl`):

- All-upcast triples present in the test: **1** (`Int→Num→Str`).
- Of those, violations: **1** — the kind-(2) precision miscompile.
- Non-upcast triples that nonetheless compose cleanly: **21**.

So the law is real — its single instance is exactly the one acknowledged bug —
but it constrains one triple, and "is an upcast" does NOT predict agreement:
21 downcast/sideways triples agree anyway. Two consequences:

1. **Do not ship "upcasts must compose" as the headline law.** It would be a
   green test that checks almost nothing, and it would imply the 21 agreeing
   non-upcast triples are unconstrained when in fact they are the bulk of the
   recorded truth.
2. **The upcast sub-category was under-tested. It has now been measured, and
   the answer settles the object-map-vs-arrow-map question.**

   The reason only one all-upcast triple appeared is mechanical: `@REPRS`
   (`coercion-composition-law.t:172`) omits `Scalar`, and every other
   all-upcast triple routes through it. Adding `Scalar` to that list and
   re-running (`scratchpad/comp-experiment.t`, 110 new rows) gives:

   | triple | AGREE | DIFFER |
   |---|---|---|
   | `Int→Str→Scalar` | 7 | 0 |
   | `Num→Str→Scalar` | 3 | 0 |
   | `Int→Num→Scalar` | 5 | **2** |

   The 2 failures are exactly the `2^53` and `2^53+1` probes. **Zero upcast
   compositions that avoid `Num` differ, on any probe.**

   So kind (2) is not the corner of a general upcast failure. It is
   `Num ↦ double`, isolated, and it shows up wherever an upcast route passes
   through `Num` and the value exceeds the mantissa. **The fix belongs in the
   OBJECT map**, confirming what `coercion-composition-law.t` already argued
   from first principles — *"nothing about the TYPE Num requires a float
   REPRESENTATION"* — and it is now measured rather than reasoned.

   This also means the upcast law is worth stating after all: with `Scalar`
   enumerated it covers 17 rows across 3 triples, of which exactly 2 fail, and
   those 2 have a single named cause.

The other arrows remain governed by the characterization, which is the right
instrument for a relation that is deliberately incoherent.

## What this changes about the design

The functor doc's items 1–5, re-judged:

1. **"`%CANDIDATES` is `F` on objects; add `F` on arrows"** — keep the second
   table, but it is not indexed by subtype edge. It is a table over the 24
   conversion pairs, with each entry tagged `upcast` / `downcast` / `sideways`.
   The tag is what carries the algebra; without it the table is just the 19
   branches rewritten as data, which buys nothing.
2. **The composition law is already tested** — stands, and is now sharper: the
   test should distinguish "this pair is required to compose" (both legs
   upcasts) from "this pair is characterized". Only the former can be a
   regression.
3. **Identity** — stands. `F(id) = id` is `return $input_ref if $from eq $to`,
   and it should be stated as a law rather than left as an early return.
4. **The refinement check moves to the source category** — stands, and the
   measurement strengthens it: `is_subtype` in the target is meaningless
   because the target has no subtyping, and 17 of the arrows aren't subtype
   questions in the source either. The vtable check should ask the conversion
   table "is there an arrow, and is it total?", not "is there a subtype edge".
5. **The corpus needs both vocabularies** — stands, untouched by this.

## The literature names this structure, and confirms the measurement

Prior-art search (2026-09-04) against primary sources. The short version: the
"functor on the subtype poset" hypothesis is correctly rejected, the right
replacement has a name, and the upcast/downcast asymmetry measured above is a
*theorem* elsewhere rather than a convention here.

**The domain is a coercion category, deliberately NOT the subtype poset.** In
Breazu-Tannen, Coquand, Gunter & Scedrov, *Inheritance as implicit coercion*
(Information and Computation 93(1), 1991), the source order is the INDEX and
the coercions are arrows in the TARGET; nothing constrains target arrows to
source edges. Sharper still, Luo, Soloviev & Xue, *Coercive subtyping: theory
and implementation* (Information and Computation 223, 2013) extends a theory by
a **set `C` of basic coercion judgements chosen by the designer**, not derived
from a pre-existing order. That is exactly our 24-entry table, and our 17
non-subtype arrows are unremarkable in that framing.

**The upcast/downcast split is the ep-pair structure.** New & Ahmed, *Graduality
from Embedding-Projection Pairs* (ICFP 2018), Definition 5.1 and **Lemma 5.2
"Embeddings are Pure"**: embeddings always produce a value with no effects,
while projections are only *terminating* — they may error. Total-and-free
upcast, partial-and-checking downcast, proved rather than stipulated. They also
show every cast **factors** as an upcast followed by a downcast.

**Our 7/7/10 partition is close to a known normal form.** Siek & Wadler,
*Threesomes, With and Without Blame* (POPL 2010), on Henglein's coercion
calculus: any coercion is φ-reducible to `c⁺ ∘ c* ∘ c⁻` — a negative
(downcast), a neutral, and a positive (upcast). That is a principled default
ordering for a preferred path: **down, neutral, up.**

**Incoherence is legitimate and has precedent.** Luo et al. define coherence as
path-agreement (their Definition 2.2, condition 3) — and note that "some
coercions are incoherent, although very useful", and that coherence checking is
**undecidable in general** once coercion rules are admitted. So "derive the
closure and verify it" is not available as a strategy. Their Example 2.1 of
incoherence is `A ≡ Nat`, `B ≡ Bool` — our `Int→Boolean` arm is the textbook
case. The documented obligation is to designate a preferred path and RECORD the
incoherence, which is precisely what `coercion-composition-law.t` does.

**No real compiler derives paths, and several fail loudly instead.** Checked:
MLIR's `TypeConverter` is a first-match-wins linear scan with no transitive
closure (register A→B and B→C and `convertType(A)` yields B, never C); PyPy's
RTyper raises `TyperError("don't know how to convert from %r to %r")` rather
than searching for an intermediate; Truffle's `lookupCast` returns `null` for
an underived pair; GCC's `useless_type_conversion_p` writes its lattice **in a
comment as a programmer obligation** and never computes it. LLVM is the
outlier worth stealing from: `CastInst::castIsValid` uses STRICT width
inequalities so that at most one opcode is valid for any type pair — the table
is unambiguous *by construction* rather than by priority ordering.

**And the naive-closure failure mode is documented as ours.** Luo et al. §5.1.2:
given `A <c1 B` and `A <c2 C`, introducing `B <c3 C` generates a composite
`A→C` that conflicts with `c2`, and the prescribed response is to reject **not
only the composite but the edge `c3` that induced it**. That is our
`Int→Boolean→Str` ≠ `Int→Str` conflict exactly.

### What this changes about the plan

Nothing about the measurement; it corroborates it. It changes two design
choices:

1. **Do not build a closure or a path search.** Every compiler checked uses a
   flat, hand-enumerated pairwise table, and the one formal treatment of
   auto-derivation says the closure is undecidable to verify. The 24-entry
   table stays flat and explicit.
2. **A missing cell must be a loud error, not a silent identity.** PyPy's
   `TyperError` is the model, and PyPy also asserts the POST-condition on every
   conversion (`if v.concretetype != r_to.lowleveltype: raise TyperError`) —
   four lines that catch a cell lying about the repr it produced. Worth
   copying; that is the class of defect the `Print`/`%Slot` bug was.

Unverified from this search: whether MLIR intends registered conversions to be
confluent (the docs never raise it — absence of documentation, not documented
absence). Reynolds 1991 and Thatte 1990 were not obtained in full text.

## What is still not established

- Whether kind (2) is fixed in the object map (`Num ↦ double` is the wrong
  choice) or by forbidding the `Int→Num` arrow where the value cannot be
  represented. The composition test argues the former; not settled here.
- Whether `Str→Scalar` and `Undef→Scalar` are the same arrow. They box into
  different tag slots, so they are likely distinct morphisms sharing an
  implementation. Unchanged from the functor doc.
- Any number for what the arrow half unblocks. Still unmeasured; F22
  (polymorphic callee) is the named candidate.
- Whether the 6 pairs with no explicit branch are reachable. Five are `X→Undef`,
  which is a discard rather than a conversion and probably should not exist;
  `Num→Scalar` is served by the generic `$to eq 'Scalar'` boxing arm, so the
  table is complete over meaningful pairs.
