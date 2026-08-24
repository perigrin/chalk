# How well typed is the IR, and how would we tell?

**Date:** 2026-08-24
**Status:** MEASURED. **No defect found — the two apparent gaps are a
deliberate, documented division of labour.** Filed for the instrument and for
the corrected numbers, not because anything needs fixing.
**Found by:** perigrin asking *"is the producer doing everything it can to make
sure everything is fully typed with as narrow a type as possible? How can we
tell?"* — and then, on being shown "93% typed", *"93% types at what width? 93%
Unknown isn't actually usefully typed."* Both pushes were right and both
changed the answer.

## The instrument, which is the durable part

"What fraction is typed" is the wrong single number: a graph with every node
stamped `Scalar` scores 100% and tells the backend nothing. Four measurements
are needed, and each catches what the previous one hides:

1. **Coverage** — % of `Value` nodes not stamped `Unknown`. Catches "nothing is
   typed at all".
2. **Width distribution by lattice depth** — `Unknown`=0, `Scalar`=2, `Str`=3,
   `Num`=4, `Int`=5. Catches the failure coverage hides: a wide-but-non-Unknown
   hedge.
3. **Derived-only split** — exclude `Constant`, `ArrayRef`, `HashRef`, whose
   width is read off the SV rather than inferred. This is the number that
   reflects INFERENCE rather than the producer's ability to copy a flag.
4. **Per-op `Unknown` census WITH INPUTS PRINTED** — turns "which nodes are
   unknown" into "which are DERIVABLE and unknown", which is the actionable
   form. This is what exposed that the remaining two were not derivable *here*.

## The numbers, over 20 representative programs (82 Value nodes)

    TYPE        N     %   depth
    Int        48   59%   5
    Str        11   13%   3
    Num         6    7%   4
    Unknown     6    7%   0
    Boolean     5    6%   4
    ArrayRef    3    4%   4
    HashRef     2    2%   4
    Undef       1    1%   3

    WIDE   (depth<=2: Unknown/List/Scalar/Void):  6 (7%)
    NARROW (depth>=3):                           76 (93%)

**Nothing lands at a wide-but-non-`Unknown` type.** Zero `Scalar`, zero `List`,
zero `Void`. The distribution is bimodal — either a narrow concrete type or
`Unknown`, with no hedging middle. That is the answer to "93% at what width":
the 93% is genuinely narrow, and the 7% says nothing at all rather than saying
something useless.

Derived-only (31 nodes, excluding the read-off-the-SV ops): **81% narrow, 19%
`Unknown`**. That is the honest inference-quality number.

## The 19% is entirely `Subscript` and `Call` — and it is CORRECT

Both looked like missed derivations. The inputs are right there:

    Subscript -> Unknown   inputs: ArrayRef:ArrayRef, Constant:Int, MemStart:-
    Call      -> Unknown   inputs: Constant:Int

Measuring the wire AND the loaded graph shows why that reading was wrong:

    CASE                   OP           WIRE stamp   LOADED representation
    array elem const idx   Subscript    Unknown   -> Int
    array elem OOB         Subscript    Unknown   -> Slot
    hash elem              Subscript    Unknown   -> Int
    arrayref elem          Subscript    Unknown   -> Int
    call Int               Call         Unknown   -> Int
    call with arg          Call         Unknown   -> Int
    call Str               Call         Unknown   -> Str

**Every one is resolved by the loader**, to the correct narrow answer.

### The OOB row is two different questions, and the columns are two vocabularies

perigrin, reading the table: *"OOB should be typed Undef since that's the value
it has."* Correct **about the type**, and the row is still correct — because
the right-hand column is not a type.

- **TYPE** (the lattice, `TypeLibrary`): an out-of-bounds read yields perl's
  `undef`, so its type is `Undef`. It is a lattice member (`Undef => 'Scalar'`,
  `TypeLibrary.pm:21`).
- **REPRESENTATION** (the machine vocabulary): `Slot`, the `{defined, payload}`
  tagged pair documented at `Chalk::IR::Node.pm:44`. **`Slot` does not appear
  in `TypeLibrary` at all** — measured, zero occurrences. It is not a type and
  cannot be one.

The loader calls `set_representation`, so `Slot` is the right answer in the
field being set. The two vocabularies OVERLAP on most names (`Int`, `Str`,
`Num`, `Boolean`, `Undef` are all in both), which is exactly why `Slot` vs
`Undef` reads as a contradiction rather than as two axes — and `Undef` is
itself a valid representation too (`%LOWERABLE_STAMP`,
`Serialize/JSON.pm:30`), so the overlap is genuine rather than a coincidence of
spelling.

**An earlier revision of this document printed that column under a "TYPE"
heading, which is the exact conflation
`2026-08-14-representation-is-the-targets-type-system.md` exists to prevent.**
Corrected here. The takeaway is not that the code is wrong but that a table
mixing the two vocabularies invites this misreading — as it just did.

### MEASURED, and the gap is real — and larger than the OOB case

Checking the `stamp` field (the TYPE axis) rather than `representation` on the
loaded graph:

    CASE             OP         stamp/TYPE   representation
    OOB read         Subscript  UNDEF        Slot
    in-bounds        Subscript  UNDEF        Int
    missing key      Subscript  UNDEF        Slot
    OOB read         Constant   UNDEF        Int
    explicit undef   Constant   UNDEF        Undef

**Every node in every loaded graph has `stamp` = UNDEF.** Not `Unknown` — the
raw absence. Constants included, whose type the wire states explicitly.

The cause is one line. `Chalk::IR::Serialize::JSON:548`:

    if (defined $nd->{stamp} && $LOWERABLE_STAMP{ $nd->{stamp} }) {
        $node->set_representation($nd->{stamp});
    }

The wire stamp is read ONLY to derive a representation, and **the loader never
calls `set_stamp` — measured, zero occurrences in the file.** So chalk drops
the type axis on load: the producer computes types, sends them, and the
consumer converts each to a machine representation and discards the type.

Two consequences:

1. **perigrin's point stands, and generalises.** The OOB read's type is not
   `Undef`; it is nothing at all. Neither is the in-bounds read's `Int`. Asking
   any loaded node for its type gets `UNDEF`.
2. **`UNDEF`, not `Unknown`.** This is precisely the absence-vs-value
   distinction the producer-side work eliminated (`54bcb9e` made the stamp
   required and `Unknown` the honest non-answer). The chalk side still has the
   three-way overload the split was meant to kill — see
   `2026-08-21-unknown-is-a-type-absence-is-not.md` and
   `2026-08-23-goto-silently-dropped.md`.

Whether this MATTERS depends on whether anything downstream of the loader wants
a type rather than a representation. The backend asks `_require_repr`, so the
lowering path is unaffected — which is why this has gone unnoticed. But it
means the loaded graph cannot answer a type-lattice question at all, so any
future pass wanting `is_subtype` or `join` over loaded nodes has nothing to
work with, and the invariant checker cannot verify a type contract it has no
types for.

Filed as its own finding rather than fixed here: setting `stamp` on load is a
small change, but deciding whether the type axis is meant to survive the wire
is a design question, not a bug fix.

### Why the producer must NOT stamp these

Not an oversight; it is load-bearing in both cases, and documented in the
producer at three sites (`FromOptree.pm:723`, `:3072`, `:3123` — *"the element
type lives on the loader side"*).

- **`Subscript` at a CONSTANT index** must stay unstamped so the loader's
  `_static_miss` (`Chalk::IR::Serialize::JSON:1709`) can prove an out-of-bounds
  literal read and re-type it `Slot`. Stamping it `Int` in the producer
  suppresses that analysis and makes an OOB read print the payload `0` — a
  silent miscompile, pinned by corpus `references.md` R9. Note the producer
  DOES stamp the dynamic-index case (`:2163`), where no static proof is
  possible and a loop accumulator over an element would otherwise lose its
  stamp.
- **`Call`** cannot know its callee's return type: the callee graph is resolved
  by the loader from the MOP. The producer emits the callee graph; the loader
  is the first point where the two are connected.

## Conclusion

**The producer is typing everything it can from where it stands.** The
remaining `Unknown`s are a HANDOFF, not a gap — the loader is the first place
the missing facts (a container's element type, a callee's return type) exist at
all. Answering the original question directly: yes, and at a narrow width — 81%
of inference-derived nodes get a concrete type, with no wide-but-non-Unknown
hedging anywhere.

**But the pipeline does not preserve what the producer computed.** The loader
converts every stamp to a representation and never stores a type, so the loaded
graph's type axis is uniformly `UNDEF`. Types survive as far as the wire and no
further.

So the honest summary is two answers, not one:

| axis | producer | wire | loaded graph |
|---|---|---|---|
| TYPE (lattice) | 81% narrow, 19% `Unknown` | carried | **absent — all UNDEF** |
| REPRESENTATION | n/a | derived at load | complete and correct |

The lowering path is unaffected, because the backend asks for a representation.
The cost is that no pass after the loader can ask a type-lattice question.

## What is NOT established

- Whether the 20 programs are representative. They cover arithmetic, strings,
  comparisons, loops, aggregates, calls, regex, ternaries and interpolation,
  but they are hand-written and small; a sweep over the ring would be a
  stronger sample.
- Whether any node reaches the BACKEND still `Unknown`. This measured the
  loader's output, not `_require_repr`'s input after every pass has run.
- Nothing here measures whether a narrow type is CORRECT — only that it is
  narrow. A confidently wrong `Int` scores identically to a right one.