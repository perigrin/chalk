# Give the loader an analysis pipeline, so lowering has a trustworthy input

**Date:** 2026-08-24
**Status:** PLAN. Not started. Scope measured; sequencing proposed; open
decisions listed rather than assumed.
**Origin:** perigrin —

> ok so we still have a GIGO problem with lowering, we're not sure that the IR
> graph that we get to *lower* is 100% accurate and the best it can be … let's
> build a plan to clean up the Loader to build the most accurate IR it can
> which includes a second pass to resolve things that require whole-program
> analysis … I think that'll include more than just the return values, but also
> a bunch of the analysis we were just discussing needing *before* the Lowering
> pass.

## The problem, stated as measured

Lowering consumes whatever the loader produces. Three findings from today say
that input is neither verified nor as good as it could be:

1. **The wire's answers are discarded, not validated**
   (`2026-08-24-wire-metadata-is-discarded-not-validated.md`). Measured over 15
   subs: the producer ships `return_type`, chalk never consults it for typing,
   and independently re-derives the same fact. 11 agree, 4 are `Unknown` on the
   wire where the loader does better, **0 disagree** — but nothing compares
   them, so a future divergence would be silent.
2. **The type axis does not survive the wire**
   (`2026-08-24-how-well-typed-is-the-ir.md`). `set_stamp` has zero callers in
   all of `lib/`; every loaded node has `stamp = UNDEF`. The producer's 81%
   narrow typing arrives and is converted to representations, node by node, at
   deserialization time.
3. **Analysis is smeared across the deserializer**
   (`2026-08-24-two-ir-architecture-alignment.md`). 18 of 19
   `set_representation` sites are in the loader; the target has 31
   `_require_repr` assertions and 13 scattered `repr eq 'Scalar'` refusals —
   the audit's phrase was "the signature of a missing prior pass".

**GIGO is the right diagnosis.** The lowering pass cannot be more correct than
its input, and today nothing establishes what that input guarantees.

## The enabling discovery: this is an EXTRACTION, not a rewrite

Measured — every analysis in `from_json` already has a graph-only signature:

    _resolve_direct_calls        ($graphs)
    _seed_and_propagate_reprs    ($graphs)
    _seed_direct_call_arg_reprs  ($graphs)
    _insert_str_coercions        ($graphs)
    _narrow_unknown_coercions    ($graphs)
    _stamp_field_access_reprs    ($classes, $graphs)
    _stamp_method_call_reprs     ($classes, $graphs)
    _infer_param_field_types     ($classes, $graphs)

**None takes `$data`. None touches the JSON.** They are already graph-to-graph
analyses that merely happen to be *called from* the deserializer. `from_json`
is 119 lines invoking them 13 times — `_seed_and_propagate_reprs` alone 5 times
— around two `while` fixpoints.

74 of those 119 lines are comment. The ordering is heavily documented and was
evidently hard-won. **That is an argument for moving this machinery intact, not
for redesigning it.**

## THE SCOPE RULE (perigrin, 2026-08-24)

> I think no matter what `%STAMP_TO_REPR` dies and is replaced by the lowering
> graph-rewrite that we haven't done yet … the Loader **is only** concerned
> with building a well typed Chalk IR.

This is a stronger constraint than the slices below were originally written
against, and it settles more than `%STAMP_TO_REPR`. If the loader's only job is
a well-typed Chalk IR, then **every representation assignment in the loader is
out of scope** — the table is just the most visible instance.

Measured, and the scale is the point: **18 `set_representation` sites in the
loader, 16 of them inside the eight analyses.** Every one of the eight assigns
representations.

    _resolve_direct_calls          1
    _stamp_field_access_reprs      2
    _seed_and_propagate_reprs      2
    _propagate_computed_reprs      6
    _stamp_method_call_reprs       1
    _seed_direct_call_arg_reprs    2
    _insert_str_coercions          1
    _narrow_unknown_coercions      1
    _infer_param_field_types       0

**But most of that is TYPE work wearing representation's clothes.**
`_propagate_computed_reprs`, the largest at 6 sites, computes `_join_repr` over
operand types and applies a per-op result rule (`%_COMPUTED_REPR`) — that is
type propagation over the lattice. The only genuinely machine-level thing in it
is `Slot`, which
`2026-08-24-there-should-be-no-representation-field.md` already measured as the
sole representation-vocabulary member that is not a lattice type name.

So the rule does not delete these analyses. It **retargets** them: they compute
types, and should write the type field. What leaves the loader is not the
analysis but the *vocabulary translation* — `%STAMP_TO_REPR`, `%LOWERABLE_STAMP`,
`Slot`, and `_repr_to_llvm_type`'s inputs — all of which become the lowering
rewrite's job.

**Consequence for the slices below:** slice 3 ("preserve the type axis") stops
being an additive step and becomes the CENTRAL one. The loader should write
`stamp` and stop writing `representation` entirely. Slice 2's assertion is then
type-vs-type rather than type-vs-repr, which is a cleaner comparison than the
one measured today.

**Consequence for `%STAMP_TO_REPR`:** the producer's surviving copy
(`SoN/IR/Serialize/JSON.pm:24`, flagged in
`2026-08-24-plan-doc-staleness-audit.md`) needs no separate remediation. It dies
with the same rewrite.

## The shape

    from_json($json)             ->  a decoded graph set, and NOTHING else
    Analysis->run($graphs, $mop) ->  a WELL-TYPED Chalk graph set
                                     (stamps only; no representations)
    Lowering->run($graphs)       ->  a target-specialized graph   [FUTURE]
                                     (types rewritten to machine types;
                                      %STAMP_TO_REPR and Slot live HERE)
    Target->emit($lowered)       ->  LLVM text                    [FUTURE]

The boundary between lines 2 and 3 is the scope rule above: everything the
loader does is on the TYPE side of it.

Only the first two are in this plan's scope. The second two are
`docs/architecture/ir-and-lowering.md`'s DESIGNED section and are named here
only so the boundary is clear.

## Slices

Each slice is independently landable and independently verifiable. The corpus
gate must read `gate-green=218 behavior=218 shape=218 invariant=218 worklist=0`
after every one; the executable gate must stay 8/8.

### Slice 1 — extract, change nothing

Move the 8 analyses and the 13-call sequence out of `from_json` into a new
module (`Chalk::IR::Analysis`, name open). `from_json` decodes and returns; the
caller runs the analysis explicitly.

- No logic changes. No reordering. The comments move with the code.
- `from_json`'s existing callers get one added line, or a convenience wrapper
  keeps them working — a decision, see OPEN below.
- **Verification is the whole point of doing this first:** if the gate holds at
  218 across a pure move, the sequence is genuinely separable and every later
  slice is safe to attempt. If it does not, the coupling is real and this plan
  needs rethinking before slice 2.

### Slice 2 — seed from the wire, and ASSERT

Today `_stamp_method_call_reprs` rebuilds `return_type` from scratch. Instead:

- seed each sub's return type from the wire's `return_type`;
- iterate ONLY over the ones that are `Unknown` (measured: 4 of 15);
- **when the wire commits to a type and the analysis derives a different one,
  that is a defect — die loudly.** Zero disagreements measured today, so this
  assertion should be free. If it fires, it has found a real bug in one side.

This is the "validate/update rather than discard/rebuild" distinction. It is
strictly less work than today AND converts a silent divergence into a loud one.

### Slice 3 — move the analyses onto the TYPE axis  ← THE CENTRAL SLICE

Under the scope rule this is no longer "additively preserve the type axis". It
is the point of the whole plan: **the loader should write `stamp` and stop
writing `representation`.**

- Call `set_stamp` on load (today: zero callers in all of `lib/`).
- Retarget the eight analyses' 16 `set_representation` calls to `set_stamp`.
  Most are already type computations — `_propagate_computed_reprs` joins
  operand types over the lattice — so this is a field change, not a logic
  rewrite.
- `%LOWERABLE_STAMP` does not carry over. It gates on a six-name set and
  measurably DROPS 6 of 45 stamps including `ArrayRef`/`HashRef`; the type axis
  has no reason to inherit a gate that exists because the *representation*
  vocabulary is smaller.
- `Slot` does not carry over either — it is not a lattice member. Wherever the
  loader currently assigns it, the honest type is `Undef` (an out-of-bounds read
  yields perl's `undef`), and `Slot` is the lowering pass's encoding decision.

**The hard part is the transition, not the change.** The backend reads
`representation` at 43 sites and branches on it 94 times. Until the lowering
rewrite exists there is nothing to produce those representations, so this slice
cannot simply stop writing them without breaking every lowering path.

Two candidate strategies, and this is an OPEN decision:

- **(a) Dual-write** — set both `stamp` and `representation` from the same
  computation, then delete the representation half when the lowering pass
  lands. Keeps the gate green throughout; carries a known hazard, since this
  project has a documented history of dual-write transitions that never
  completed their second half (`CLAUDE.md`, MOP migration).
- **(b) A shim in the target** — the backend derives a representation from the
  node's stamp on read, as a temporary stand-in for the lowering pass. Smaller
  and more honest about where the translation belongs, but it puts translation
  logic in the target, which is where it must NOT end up.

### Slice 4 — the whole-program analyses

The passes that genuinely need a program-wide view, which is what perigrin
means by "more than just the return values":

- **call-graph resolution** — `_resolve_direct_calls` / `_attach_call_targets`,
  already whole-program, currently interleaved;
- **argument-type seeding** across call boundaries (`_seed_direct_call_arg_reprs`);
- **container monomorphism** — the analysis
  `2026-08-24-chalk-memory-model-baseline.md` §4a identifies as the real
  question behind `ArrayRef[Int]`: is this container's element type stable over
  its whole lifetime, across all stores? Today `_element_repr` answers a
  narrower question (are the INITIALIZERS homogeneous) and the store path GAPs
  rather than falling back;
- **escape / no-tie** — needed before any provenance narrowing can be trusted
  (`2026-08-24-access-provenance-and-the-mop.md`). Note the self-hosting subset
  makes this trivially true today (0 `tie` sites, measured), so this can be an
  assertion before it is an analysis.

### Slice 5 — state the contract

An invariant the analysis pipeline guarantees on exit, checkable, so lowering
can rely on it: e.g. *every `Value` node has a representation, or the graph is
GAP-declared with a named reason*. Today 31 `_require_repr` assertions in the
target are each independently discovering this is not guaranteed.

## What this plan does NOT do

- It does not build the lowering pass. It builds a trustworthy input for one.
- It does not remove the `representation` field
  (`2026-08-24-there-should-be-no-representation-field.md`). That is the
  lowering pass's job; this plan makes the type axis survive so that becomes
  possible.
- It does not touch `Chalk::Target::*`. The class conversion (task #42) is
  independent and in flight.

## OPEN — decisions needed before or during

1. **Does `from_json` keep a convenience wrapper**, or do all callers change?
   40 files reference it, but the breakdown makes this MUCH cheaper than that
   number suggests — measured:

   | location | files | what they are |
   |---|---|---|
   | `t/bootstrap/**` | 34 | unit tests wanting "a loaded graph" |
   | `t/lib/.../Harness/` | 3 | `ProgramRunner`, `Mode2Adapter`, `Phase5LibCoverage` — the real pipeline |
   | `lib/` | **1** | the file that DEFINES it |

   **No production code calls `from_json` at all.** The only `lib/` hits are the
   definition plus three comments. So the churn is: 3 harnesses take an explicit
   analysis step (they already sequence the pipeline), and 34 unit tests are
   exactly the population a convenience wrapper exists for.

   Worth recording separately, because it is a larger observation than this
   plan: **the end-to-end pipeline (`B::SoN` → `from_json` → LLVM lower) exists
   only under `t/lib/`.** `script/` has `chalk-emit-son-json` for the producer
   half and nothing for the consumer half. Given the project's stated goal that
   "the output is EXECUTABLES", that the only driver is a test harness is a
   finding in its own right. Not this plan's to fix. Consumers also span both
   corpus harness
   modules. A wrapper is less churn; explicit is more honest about the phase
   boundary.
2. **Where does the analysis live** — `Chalk::IR::Analysis`, a set of passes
   under the existing `Chalk::Bootstrap::Optimizer::Pass` contract
   (`run($X) -> $X`, already specified and unused for this), or something else?
   The `Pass` contract already exists and is documented for exactly this shape.
3. **Is the assertion in slice 2 fatal or a warning** at first? Fatal is the
   project's GAP-not-miscompile stance; a warning would let it soak. Measured
   zero disagreements argues fatal is safe immediately.
4. **Does slice 3 keep `%LOWERABLE_STAMP`?** It gates representation seeding on
   a six-name set. The type axis has no reason to inherit that restriction, but
   removing it changes what reaches the backend.
5. **Order of slices 3 and 4.** Slice 4's container analysis may want the type
   axis present (slice 3) to express its result. Not established.

## Measurement caveats carried forward

- The 15-sub agreement measurement covers only plain `main::` subs. **Methods
  on classes are unmeasured**, and `_stamp_method_call_reprs` is specifically
  about methods. Slice 2 should re-measure on methods before relying on "zero
  disagreements".
- `Context.pm` counts elsewhere in today's docs were taken while another agent
  was mid-edit; they carry a small race. The counts in THIS document
  (`from_json` at 119 lines, 8 pass signatures, 13 invocations) were taken
  directly and are not affected.
