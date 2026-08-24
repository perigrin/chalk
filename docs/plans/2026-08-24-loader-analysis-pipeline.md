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

**THE TRANSITION MECHANISM (perigrin): make the representation API a temporary
ALIAS for the stamp API.** Not two stored values — one field, two names:

    method set_representation($r) { $self->set_stamp($r) }   # DEPRECATED alias
    method representation()       { $self->stamp }            # DEPRECATED alias

This is better than either option originally written here, and it is better for
a structural reason rather than a stylistic one.

- **There is no second stored value, so nothing can diverge.** The hazard of a
  dual-write is two sources of truth rotting apart; an alias has one source of
  truth, so that failure mode is unreachable by construction. Given this
  project's documented history of dual-write migrations whose second half never
  landed (`CLAUDE.md`: `body` arrayrefs dual-written with 15 reader sites still
  outstanding), that matters more than the mechanism's simplicity.
- **The deletion becomes compiler-enforced.** When the lowering pass lands,
  delete the alias; every remaining caller fails to compile. That is a
  mechanical endpoint, not a discipline-enforced one.
- **The translation is not in the target.** It is a deprecated name on the IR
  node, which is the right place for a name that is going away.
- **The backend needs no edits at all** during the transition — its 43 reads
  and 94 branches keep working.

**Feasibility, measured.** The alias is only sound where a representation value
is also a valid lattice type. Every literal `set_representation('...')` in
`lib/`:

    set_representation('ArrayRef')    lattice type  ✓
    set_representation('Boolean')     lattice type  ✓
    set_representation('Regex')       lattice type  ✓
    set_representation('Slot')        NOT a type    ✗   (one site,
                                                        Serialize/JSON.pm:1547)

**Three of four are lattice members. `Slot` is the sole exception, at exactly
one site** — the `_static_miss` out-of-bounds branch. Its honest type is
`Undef` (an OOB read yields perl's `undef`), so that one line becomes
`set_stamp('Undef')` and the `Slot` ENCODING moves to the lowering pass, which
is where this plan says it belongs anyway.

Non-literal assignments (computed values from `_join_repr` and friends) are
lattice joins by construction, so they alias cleanly.

**Open sub-question:** whether the alias should WARN on use. A warning would
make the remaining call sites visible without breaking them, at the cost of
noise in every test run. Probably better to leave it silent and rely on the
compile-time break at deletion.

### What the pipeline IS, named properly (perigrin, 2026-08-24)

> Note that the Loader *should do* a Type Inference and Type Check pass … which
> is I believe the whole-program analysis we were discussing anyway … this is
> basically a final pass to ensure that the Graph is Type Safe **and** as Narrow
> as possible.

That names the thing the slices below were circling, and it splits into **two
distinct obligations** this plan had been conflating:

| obligation | question | failure mode |
|---|---|---|
| **INFERENCE** | is every node as narrowly typed as derivable? | a `Unknown` that could have been `Int` — lowering GAPs or boxes needlessly |
| **CHECKING** | is every node's type CONSISTENT with its operator and operands? | a wrongly-typed node reaches lowering and miscompiles |

Inference makes it narrow. Checking proves it safe. **They are not the same
pass and they can fail independently** — a graph can be maximally narrow and
still ill-typed, or type-safe and uselessly wide.

#### The checker already exists — and it is a TEST, not a compiler pass

`Chalk::IR::Graph::TypedInvariant` implements exactly this: `%OP_REQUIRED_REPR`,
per-position operand checks (`_check_repr_for_position`), and `_conforms`
resolving subtype relations through `TypeLibrary`.

**But measured: nothing in `lib/` calls it.** Its only consumers are
`t/bootstrap/**` — including `son-corpus-wide.t:240`, where it is the corpus
gate's `invariant` leg (the fourth number in
`gate-green=218 behavior=218 shape=218 invariant=218`).

So the compiler never checks its own graph. The check runs, thoroughly, in the
test suite — which means an ill-typed graph produced outside a corpus case is
caught by nothing. That is the same shape as the other findings today: the
machinery exists, the consumer does not use it.

**And it checks REPRESENTATIONS, not types** — `$node->representation()` at
`:367` and `:382`. Under the scope rule above it must become a check over
`stamp`. That is not a rename: `%OP_REQUIRED_REPR` was measured earlier this
week to be load-bearing for exactness (`Divide`/`Concat`/`Length`), and
converting `_conforms` from `eq` to `is_subtype` was tried and killed on
measurement. Retargeting it to the type axis has to re-answer that question.

#### What this means for the plan

Slices 2 and 4 are the INFERENCE half. Slice 5 ("state the contract") is the
CHECKING half, and is no longer a vague aspiration — it is *"run
`TypedInvariant` as the pipeline's exit gate, over stamps"*. The 31
`_require_repr` assertions in the target are each a symptom of that gate not
existing: the backend re-discovering, one node at a time, that nothing upstream
guaranteed what it needs.

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

### Slice 5 — the TYPE CHECK, as the pipeline's exit gate

Not a new mechanism: **run `Chalk::IR::Graph::TypedInvariant` at the end of the
analysis pipeline, in `lib/`, over stamps.** Today it runs only in tests, and
only over representations.

The contract it establishes, which lowering may then assume:

- every `Value` node carries a stamp (guaranteed structurally on the producer
  side since `54bcb9e`; must hold after chalk's analyses too);
- every node's stamp CONFORMS to its operator's requirement and its operands'
  stamps, per `%OP_REQUIRED_REPR` / `%OP_PER_POSITION_REPR`;
- a graph that fails is a GAP with a named reason, not a silent pass-through.

Prerequisites, both real:

- **slice 3 must land first** — there are no stamps to check until the analyses
  write them.
- **`%OP_REQUIRED_REPR` must be re-examined on the type axis.** It is currently
  exactness-based, and that exactness was measured to be load-bearing:
  converting `_conforms` from `eq` to `is_subtype` was attempted and killed on
  measurement (`2026-08-14-representation-is-the-targets-type-system.md`). The
  same table over TYPES may need different answers, since `Int <: Num` is a
  meaningful relation for types in a way it is not for machine encodings.

**The payoff is the 31 `_require_repr` assertions.** Each is the backend
discovering at lowering time that nothing upstream guaranteed what it needs.
With an exit gate they become redundant — and, more usefully, a failure moves
from "the backend GAPped deep in emission" to "the analysis pipeline rejected
this graph and said why".

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
