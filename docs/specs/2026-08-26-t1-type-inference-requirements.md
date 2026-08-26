# T1 — what building it actually requires

**Date:** 2026-08-26
**Status:** REQUIREMENTS. T1 does not exist. `Chalk::IR::Analysis` is a pass
sequence (eleven passes, seventeen invocations over a hash of graphs handed to
it by the loader); T1 is a transformation with a contract over ONE graph, and
the gap between them is this document.

How these requirements were arrived at — the corrections, the failed split, the
measurements — is in `docs/specs/2026-08-26-t1-derivation.md` and in the commit
log. This file is the contract only.

## 1. T1 is a CORRECTNESS transform, not an optimization

**The test:** *can the compiler still produce a correct program without this
stage?* Remove an optimizer and you get a slower correct program. Remove T1 and
the backend receives a graph it cannot lower — or lowers by guessing. **T2 is
the same**: remove it and there is no encoding at all.

So neither belongs under `Optimizer::` — they share the `Graph -> Graph` SHAPE
with optimizer passes, which is an interface, not a category. And neither may
DECLINE a case it cannot handle: an optimizer passes it through, a correctness
transform fails loudly.

**Outcome ranking.** An un-narrowed type lands in one of three places, and they
are not comparable:

| outcome | verdict |
|---|---|
| **boxed** | correct, slower. Acceptable. |
| **GAP** | no program, loudly. Acceptable. |
| **guess** | wrong program, silently. **The only unacceptable one.** |

**Boxing is okay; incorrect lowering is not.** Narrowing matters because it
moves work off the boxed path — never because the boxed path is wrong.

## 2. Entry contract

    Chalk::IR::Transform::TypeInference->new(...)->run($graph) -> $graph

- **`Graph -> Graph`**, entered from the pipeline: `Loader > T1 > Optimizers >
  T2 > Optimizers > Scheduler`. Self-hosted there is no loader (the frontend is
  chalk's own parser), so anything reachable only via `from_json` is dead code
  in the configuration that matters.
- **ONE GRAPH. There is no "graph set" in the architecture** — that is a
  serialization container (the wire's `methods` section), and modelling
  transport as architecture is what makes the contract look impossible.
  Inter-unit references are EDGES: a `Call` carries a reference to its callee,
  through which the callee's return type is reachable. Graal is the same shape
  — a `StructuredGraph` per method, with inlining pulling the callee in
  *through* the call node. There is no `Map<String, Graph>` in the design.
- **No `$classes` parameter.** Class metadata passed alongside the graph is the
  same error one level up. It belongs ON the graph, reachable — see §6.

"T1 sees the whole program" therefore does not mean "T1 is handed every graph".
It means **the program is reachable from the graph**: follow the call edge to
the callee's types, the field reference to its declared type. Requiring a set
would be an admission that those edges are missing.

## 3. Input: a PARTIALLY TYPED graph

The frontend already stamped what it could. T1's input is not an untyped graph
awaiting types; it is a graph carrying the frontend's answers, some narrow,
some `Unknown`, some absent.

- **`Unknown` is an INPUT VALUE, not a hole** — the frontend saying "I could
  not determine this", which is information.
- **T1 NARROWS, it does not assign from scratch.** It uses what a single-unit
  frontend cannot see: a callee's return type through the call edge, argument
  types through the same edge in reverse, container monomorphism over every
  store. All reached FROM the graph (§2), not supplied alongside it.
- **T1 must never WIDEN a frontend stamp without cause.** `Int` in, `Scalar`
  out is a precision regression even though both are sound. The only legitimate
  widening is a JOIN the graph requires, traceable to that merge.

**A frontend stamp is EVIDENCE, not an axiom.** Where T1 independently derives
a contradicting type, **T1 DIES, naming the node and both claims.**

Not a GAP, and not a policy about which side wins. A contradiction means one of
the two is WRONG, and both are chalk's code — so it is a bug to investigate,
not a case to have a rule for. "Prefer the derivation" and "prefer the wire"
are both ways of continuing past a self-contradiction; a GAP would claim chalk
does not support the construct, which is false when chalk supports it and
merely disagrees with itself about it.

This is slice 2's existing rule for method return types — seed from the wire,
die on disagreement, *"refusing rather than picking silently"* — generalised.
It may want revisiting once chalk is no longer under active development; while
it is, a contradiction surfacing loudly is worth more than a compiled program.

T1 checks what it computes anyway; it does not audit the producer.

## 4. Exit condition

**Absence normalizes to `Unknown` on entry.** A Value node arriving without a
stamp is treated as `Unknown`; the only difference is whether some pass wrote
the fact down. Normalizing is not giving up — an absent stamp is INVISIBLE to
inference, while `Unknown` is a lattice value every rule can act on.

> **No Value node leaves T1 stamped `Unknown`.**

On input `Unknown` is honest — one compilation unit. On output it is not,
because T1 sees the whole program, so no later phase has more to work with.

**It is a GAP, not an internal error.** Perl has constructs with no static type
at any phase (`eval "$str"`, `$obj->$name()`, runtime `@ISA`), and they need no
special handling because **an un-typeable construct is an un-lowerable one** —
same reason, so the exit condition reports early what the backend would raise
anyway. Chalk declining a construct it does not support, which implies nothing
broken.

**`Scalar` is NOT the same category.** It is a real answer and a legitimate
exit type — *"Scalar is a legitimate static answer, Unknown is an inference
failure."* So maximal narrowing is a TREND everywhere else and a BINARY here.

**Control nodes carry no stamp.** `Start`, `Region`, `If`, `Loop` define no
value; a stamp on one is corruption, not typing. The condition is over Value
nodes precisely — a checker walking "every node" is wrong in a way that looks
like progress.

**Arrived-absent is a FRONTEND bug, reported separately.** Absence is
structurally impossible at the producer, so an absent stamp on the wire means
something bypassed the constructor. Report every one **whether or not T1 later
types it** — otherwise the cheapest frontend bugs vanish from the record
precisely because T1 did its job.

## 5. Flow-sensitive refinement: a Pi-style value node

A branch is a type guard: `if (defined $x)` establishes `$x` is not `Undef` on
the then-edge. Maximal narrowing REQUIRES this — without it `$x` inside the
guard keeps its entry type.

**The refinement is a VALUE node, not an annotation on the branch.** A floating
value has no position, so the only way to say "this fact holds only here" is to
make the fact BE a value whose inputs pin it. Every floating-IR system does
this — Graal `PiNode`, C2 `ConstraintCast`, TurboFan `TypeGuard` (survey in the
derivation doc).

**The Pi's guard input is the `Proj`/`Region` for the taken branch**, so
control nodes influence stamps by being pointed at while still carrying none,
and soundness falls out of dominance with no scheduler changes. Graal's
`GuardingNode` is a marker interface with zero methods for exactly this reason
— the guard is a position, not a condition object.

Three points to copy, each with the failure it prevents:

| rule | why |
|---|---|
| store the DELTA — `piStamp` is what the guard proves; effective stamp is `piStamp ⊓ input.stamp`, recomputed, monotonic | cannot go stale when a later pass improves the input, and Chalk builds IR during parse |
| never fold the narrow stamp back onto the guarded input | *"only true at this point in the control flow"* — Graal allows it only under `guard == null && !hasMoreThanOneUsage()`, i.e. when it was not flow-sensitive |
| two independent bits: `_floating` (may it move?) vs `_narrows_type` (removable when the input is that narrow?) | C2 collapsed them and an array access floated above its range check |

**Lifecycle — three owners, and all three must be assigned or the obligation
falls between them.** Graal's division, which puts each job where the
information is:

| phase | job |
|---|---|
| **frontend** | CREATES a Pi at the guard. It is the only phase that sees `if (defined $x)` as syntax and knows the branch is a type test — Graal's main producer is likewise the bytecode parser, not a later analysis. |
| **T1** | STRENGTHENS. It knows types the frontend does not, so a Pi's `piStamp` can improve; monotonically, never widening (§5 rule 1). T1 does not create the refinement structure, only sharpens it. |
| **Scheduler** | DELETES every Pi once nodes are pinned, then re-derives positionally. A Pi's whole job is to say "this holds only here" to a value that FLOATS; once position is fixed the position says it. |

**A Pi reaching the backend is a bug** — a node with no lowering, because by
then it should have become positional information. Graal's `FixReadsPhase` is
the same boundary.

Prior art for `remove(σ, Undef)` specifically: Tobin-Hochstadt & Felleisen's
occurrence typing (POPL 2008, ICFP 2010), which names **Perl** as a motivating
language. Nullability narrowing is the base case, not a special case.

### Aliasing: start conservative

A refinement is a claim about a NAME; the value lives at a LOCATION; Perl lets
other names reach it — `foreach` aliases the loop variable to the element, `@_`
aliases the caller's arguments, `\$x` escapes, `local` swaps a package variable
across a call.

> **THE POLICY: a refinement holds only on a value that never leaves
> value-SSA.** Anything in memory is not refined. No analysis required — Chalk
> already demotes on escape.

Sound, no new machinery, costs only precision. **Liberalising it is future
optimization work** — every liberalisation has the same shape as the `%Slot`
narrowing ladder: prove the alias cannot happen, then keep the refinement.
Candidates: non-escaping locals surviving calls (Flow's two-tier model),
`foreach` over a container nothing else writes, `@_` where the callee provably
does not write, and references that never escape staying in value-SSA at all.


## 6. The MOP must ride on the IR — it IS the inter-unit edge

**This is what makes §2's one-graph contract possible, not merely honest.**

A `Call` resolves its callee through a MOP handle — the node already documents
it: *"codegen can read the callee's graph/params/return-type directly."* That
handle is the inter-unit reference. With the MOP on the IR, a `Call` can answer
"what does my callee return" from the graph it is already in, and T1 needs no
set. Without it, the only way to reach a callee is a lookup in a hash somebody
passed alongside — which is the graph-set shape §2 rejects.

Today the MOP is an *output of inference* — `_replay_classes` builds it and is
one of the eleven passes — which forces `run` to return `($graphs, $mop)` and
every consumer to take both. `_build_registry_from_mop` then rebuilds a second
copy at lowering time; with the MOP on the graph there is nothing to rebuild,
so it goes away too.

## 7. The pipeline object must exist first

§2 says T1 is "entered from the pipeline". **There is no pipeline.** Three
harnesses each run the same sequence inline:

    my ($graphs, $mop) = from_json($json);
    ... lower($ret, mop => $mop)

`ProgramRunner`, `Mode2Adapter`, `Phase5LibCoverage` — identical, copy-pasted.
That is why removing the loader's analysis call broke three places at once: the
pipeline exists three times, in test harnesses, with no single seam to change.

**Build it before wiring T1.** One object owning `Loader > T1 > Optimizers >
T2 > Optimizers > Scheduler`, with the harnesses calling it instead of
assembling their own. Then wiring T1 is one edit, and the acceptance criteria
below stop conflicting: `loader-reproduces-the-wire.t` can reach 0 (the loader
stops analysing) while the gate holds at 218 (the pipeline runs T1), because
the same change does both.


## 8. What T1 must stop inheriting from the loader

Two loader behaviours are inference, not deserialization:

1. **The `Print` → `Boolean` seed** — deriving an operator's result type from
   its semantics is inference wherever it happens.
2. **`%LOWERABLE_STAMP`** — a filter asking "can the BACKEND lower this?",
   which is the lowering phase's question. Its effect is that the loader
   discards type information the frontend sent.

Both move only when T1 exists. The exit condition settles the filter: if no
`Unknown` leaves T1, none reaches the backend, so the filter guards a case that
has stopped occurring — deletable on T1's completion.

## 9. Acceptance

Not "the gate still reads 218" — that measures behaviour over 218 programs, and
2026-08-25 shipped three real bugs with the gate green throughout.

1. **`loader-reproduces-the-wire.t` reads 0 and asserts.** Today 16, every one
   the loader overwriting what the wire sent.
2. **The five conditions hold** (`docs/plans/2026-08-24-loader-analysis-pipeline.md`
   §"What well-typed means"): total, lattice-membered, conformant, sound,
   maximally narrowed.
3. **Narrowing is measured before/after on the same graph** — the input IS the
   baseline, so no oracle is needed:
   - no stamp may widen without a merge requiring it;
   - `Unknown` count at the exit reaches ZERO;
   - arrived-absent count reported separately as a frontend metric;
   - narrowed-node count trends up per corpus case, tracked like the gate
     floor — **but only ever raised on a run where the gate holds at 218.**
     Alone it would reward the bug this spec prevents: `Int` where a `Str` can
     flow IS a narrowing and raises the count. Soundness forbids it but is a
     property to prove rather than a number to check, so pairing is what makes
     the checkable metric safe.
4. **The first version REPORTS rather than asserts** — the exit condition fails
   broadly today, and an assertion that must be disabled to land is what
   `_assert_value_nodes_are_typed` already is.
5. **The corpus gate holds at 218** as a floor, not a definition of done.

## 10. The `Unknown` join policy: ABSORB

`join(Unknown, T)` is `Unknown` — what `join_types` already does. `_join_repr`
DROPS the `Unknown` arm and joins the rest, and the loader depends on that.

```perl
my $v;
if ($c) { $v = f() }   # f's return type not yet resolved -> Unknown
else    { $v = 2 }     # Int
```

**Drop is sound only if `f`'s type is already known at the join** — only if `f`
is defined and analysed before its use. Perl does not work that way: forward
references, mutual recursion, `@ISA` resolution, a sub defined below its
caller. So drop is either unsound, or it imposes a declaration-order constraint
the language does not have.

That makes the fixpoint FORCED BY THE LANGUAGE rather than an implementation
choice, and absorb is what makes iteration work:

- **Absorb** yields `Unknown` — a sound intermediate a later round sharpens.
- **Drop** yields `Int` — an unsound one later rounds have no reason to
  revisit, because it looks resolved. The same error as the reverted `Slot`-arm
  drop: committing before the evidence is in, and self-concealing where
  `Unknown` would have advertised that work remained.

The poison-spreading objection to absorb is just non-convergence: run to
fixpoint, and a surviving `Unknown` means `f` genuinely could not be resolved,
which §4 reports at the arm that actually failed.

## 11. Open

- **`_join_repr` calling `join_types`** — tracked in the plan §4a, mostly
  subtraction. With absorb settled above, this is the change that adopts it.
- **The pipeline object's shape** (§7) — stages fixed or configurable, what it
  takes, what a caller gets back. `Phase5LibCoverage` wants per-unit results
  rather than one output, so the three harnesses define the requirement.
  Derive the shape from them when building rather than designing it here.
