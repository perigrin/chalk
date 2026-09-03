# Design: real `define` + `call` — reordered after review

**Status:** design v2, awaiting review. Not a plan; no implementation.

## v3 re-measurement, 2026-09-03 — READ BEFORE EXECUTING ANY SLICE

Measured on HEAD against pinned producer b96087c.

**Slice 0 (recursion guard) IS DONE.** The guard exists at `Context.pm:8639`
and fires cleanly on `sub f { my $n = shift; $n <= 0 ? 0 : f($n-1) }` — exit 0,
no hang. The "compiler HANGS, true exit 124" claim is stale.

**Slice 1 (epilogue suppression) IS DONE.** `program_mode` suppresses the type
tag; `print "hi\n"` gives chalk `hi` against perl `hi`, byte-identical.

**Slice 2's ACCEPTANCE CRITERION CONTRADICTS ITS OWN SCOPE.** The slice is
scoped to "a non-recursive, EFFECT-FREE, single-argument callee" and then names
corpus F12 as the case that must flip GAP -> GREEN. F12 is

    sub g { for my $i (1..2) { print "z" } 9 }

-- a loop AND a print, i.e. exactly the effect-bearing callee the slice
excludes. Measured, it GAPs at `Context.pm:8819` on the effect-on-control-chain
path. **Slice 2 as scoped cannot close F12** and needs a real acceptance case
before it is executable. Note also that an effect-free callee called twice
(`sub f { 7 }`) ALREADY lowers through the inliner, so the population Slice 2
unblocks should be measured rather than presumed.

### The `fib` typing question — a false dilemma, and the answer is already in the lattice

This doc frames Slice 3's typing prerequisite as "a seed plus a join-rule
change". The join-rule half is wrong AND actively dangerous to act on; the seed
half is right but for a different element than anyone reaching for it would
pick. The full correction is recorded because the appealing fix is a trap and
the real fix is one word.

`2026-08-21-unknown-is-a-type-absence-is-not.md` diagnoses two defects: an
unstamped arm reaches the join as a Perl `undef` (not a lattice point, so the
join bails), and `Unknown` is TOP so it wins any join it does enter. It
concludes that **`Unknown` must not participate in a join** — drop those arms,
let the base case decide.

**DO NOT IMPLEMENT THAT.** It was superseded five days later. `6a0a0b7d`
(2026-08-26) made `_join_repr` a total fold of the lattice join, deliberately
absorbing:

> `Unknown` is now a RESULT, not just an input, and it ABSORBS, so an arm
> inference could not type makes the whole merge Unknown rather than being
> discarded in favour of the known arm. That is deliberate: typing a merge from
> one arm when the other is unknown is a guess about the unknown one.

The 2026-08-21 doc's own status is `MEASURED, not fixed`, and it predates the
commit. Three further reasons not to revisit it:

- `join-is-the-lattice-join.t:84` already pins "Unknown absorbs", with an
  exhaustive agreement check over every ordered pair of the sixteen lattice
  stamps. A drop-rule would contradict a green test.
- That commit re-measured 231 corpus cases, head vs total-fold, and diffed every
  node's final stamp: **zero lines**. A drop-rule moves stamps verified stable.
- The `Undef` precedent the 2026-08-21 doc cites is a CALLER-level drop
  (`_seed_and_propagate_reprs`), explicitly preserved by `6a0a0b7d` alongside
  the TernaryExpr condition-drop. It is not licence for a drop inside the fold
  that every merge in the compiler shares.

**AND THE ANSWER IS SIMPLER THAN EITHER, AND ALREADY BUILT.** The lattice has a
BOTTOM element, `None`, and `join_types` documents it for precisely this case
(`TypeLibrary.pm:383`):

> None is the identity (T join None == T), which is what lets a recursive
> function type from its base case: the recursive arm contributes None on the
> first pass, so Int join None == Int rather than collapsing to a top.

Verified against shipped code:

    join(None,    Int) = Int        join(Int,  None) = Int
    join(None,    Str) = Str        join(None, None) = None
    join(Unknown, Int) = Unknown    <- the contrast: top absorbs, bottom yields

So the recursive arm must contribute **`None` (bottom)** — not `Unknown` (top),
which absorbs and discards the base case, and not absence, which makes the join
bail. With the right element the EXISTING join types `fib` mechanically. No
drop-rule, no special case, no cycle-breaking, and nothing to build in the join.

**What is actually missing is a seed.** Measured: nothing in `lib/` ever stamps
a node `None` for this purpose, so the recursive Call stays unstamped and
`_seed_and_propagate_reprs` bails at `Analysis.pm:2085`
(`next if grep { !defined } @reprs`) before the identity can apply. The
identity element exists, is documented for this exact use, and has no producer.

This also disposes of a more elaborate answer that looks right: "assume the
return type is the join of the known arms, then check the recursive arm is
consistent" describes a hypothesis-and-check pass to be built. That is what
`None` + the existing join already DO on the first pass, for the
one-typed-arm-plus-one-recursive-arm shape. Real iteration is still needed for
mutual recursion where no arm types on the first pass — but that is a later
generalisation, not the thing standing between HEAD and `fib`.

Also already landed and listed here as outstanding: the TernaryExpr join already
EXCLUDES the Bool condition (`Analysis.pm:2082`).

### The typing gap is upstream of the call gap, for BOTH recursion shapes

Measured after the loader, `fib` AND `down` both end with an unstamped
TernaryExpr and an unstamped Return. They differ only in which refusal is
reached first: `fib` lowers an `Add` over two calls and needs a type immediately
("Add node has no representation at lowering time"), while `down`'s recursive
Call hits the recursion GAP before any type is required.

**Consequence for testing:** a test asserting only "it refuses for a call-shaped
reason" passes for `down` today while its types are just as absent — a false
green. I wrote one before catching it.

**Consequence for ordering:** neither half alone makes `fib` compile. The
2026-08-21 doc is explicit that it "does NOT establish that `fib` compiles once
both are fixed — call emission is still required for the recursion itself; this
is only the typing half."

---
**Type-library work belongs to:** `docs/plans/2026-07-19-runtime-mop-coerce-multimethod.md`
(milestone `runtime-mop-pilot`). This design does NOT build it.

## What changed in v2, and why

v1 proposed one slice: give `Call` a memory contract with a kills-everything default,
disable the inliner, and prove it with `fib(10) == 55`. Two independent reviews found
the **insight** sound and the **ordering** wrong, and measurement refuted the
motivation.

**The motivation was a proxy metric — the second time in this project's record.** v1
ranked F3 by GAP-site count inside one function. Measured against programs actually
unblocked:

| metric | F3 as scoped in v1 |
|---|---|
| ring files unblocked (t/base, t/cmd, t/opbasic, t/comp — 40 files) | **0** |
| executable-gate programs unblocked (5) | **0** |

Both call-shaped ring blockers are **producer-side callee-body GAPs** (`until` loop,
non-lexical `foreach` iterator) — the producer never emits a graph, so a real `call`
would target a `define` that never exists. See `feedback_proxy_metrics`.

### v1 claims that measurement refuted

| v1 claim | measured |
|---|---|
| "eight GAP sites, all from having no fallback" | **13**; no grouping yields 8. **6 of 13 are `@_`-modelling** and survive F3 verbatim — a real call frame still must answer "which param does this `shift @_` read?" |
| "seed at bottom, converges in one round for `fib`" | **False.** The `Add` types to Int, but `TernaryExpr` never does: the loader's join bails when any input lacks a rank (`JSON.pm:1105`), and a ternary's inputs include the Bool condition. `fib`'s Return never types. |
| "extends the existing fixpoint machinery" | **False.** Every stamp is write-once (`next if defined $node->representation`). "Widen to fixpoint" needs re-stamping plus cone invalidation — a structurally new pass. |
| "identical to how `Assign` behaves today" | **False.** `Assign` takes **no** memory input (`inputs => [$target,$value]`); it only *becomes* the version, and only for element stores. The proposed contract matches **shift/pop** (`FromOptree.pm:2164`), not `Assign`. |
| "ir-blocks spell `Call` by attributes, not operands" | **False** — 46 of 56 spell operands. The zero-churn *conclusion* holds, but via `MdtestCorpus.pm:1371-1373`: extra **trailing** inputs are ignored. **Position-conditional** — prepending memory fails the gate. |
| "`t/base/subval.t` does not exist" | It is `~/dev/perl5/t/cmd/subval.t`. I got the directory wrong while correcting a directory error. Its first blocker is a ternary-with-element-store, not a call. |
| "15 of 160 corpus cases declare a sub" | **178 cases, 14 sub-declaring.** |
| symbol mangling needed | Unnecessary — `define i64 @"main::fib"` works (proven against lli-15). |
| `define` emission must be built | **Already exists.** `_emit_class_registry_ir` (`LLVM.pm:625-895`) emits per-method `define`s with per-repr `ret`; `_lower_call_method` emits real `call`s. A direct call is the *simpler* case. |

### The spine, corrected

v1's spine — *an assignment is a call minus uncertainty*, giving a lattice on effect
precision — is a good **description of a target**, but v1 presented it as a
description of **what exists**. Measured:

- Only **rvalue `Subscript`** is memory-versioned. `Length`, `FieldAccess`,
  `StashAccess` take no memory input; `PostfixDeref`/`Slice` aren't producer-built.
- There is **one undifferentiated memory chain with no location identity**, so the
  code has **two** precision points, not four.
- **The kill-set lattice has no consumer anywhere.** `lower_value`'s model is
  `_reads_mutable_location` cache-bypass (`Context.pm:277-352`) plus
  `_freeze_memory_reads` (`:2577`). Nothing reads a kill set.

That is the world-token pattern again: an elegant typed structure whose consumer does
not exist. **The lattice stays in this doc as a roadmap, explicitly labelled as one,
and is built only when something consumes it.**

What survives intact: **Graal's single-node contract is already Chalk's shape**, and
a call is the general case of which a store is the specialised one. That framing is
correct and still drives the design — it just does not justify building the lattice now.

---

## Ordering

### Slice 0 — recursion guard (NOT F3; do it now)

**On HEAD, the compiler HANGS on self-recursion the inliner accepts.** Measured, true
exit **124**, never terminates:

```
sub f { my $n = shift; $n <= 0 ? 0 : f($n-1) }
  -> Deep recursion on _lower_inlined_effects_then_value (Context.pm:4440)
  -> Deep recursion on _lower_ternary (Context.pm:391)
  -> timeout, exit 124
```

There is no recursion guard in `_lower_call_direct` (`Context.pm:4355-4443`). This is
a **live GAP-not-miscompile violation** — worse than a miscompile for a build system,
because it never returns. ~5 lines: a callee-name set, `local`-scoped like `_arg_bind`,
GAPping loudly on re-entry.

Independent of F3. Ship it first regardless of what happens to the rest.

### Slice 1 — `program_mode` epilogue suppression (NOT F3)

The executable gate is 1/5, and **three of the four failures are the type-tag
epilogue**, not effect ordering:

```
hello        perl "hi\n"   vs chalk "hi\nUndef:\n"
two-prints   perl "a\nb\n" vs chalk "a\nb\nUndef:\n"
arith-print  perl "5\n"    vs chalk "5\nInt:5\n"
```

One branch at `LLVM.pm:1290` plus a `lower()` option, **default off**, measured in a
shadow tree: **gate 1/5 → 4/5.** The gate's own header already names this
(`executable-gate.t:33-35`).

Must stay default-off: the corpus behavior leg reads the tag via `_expected_epilogue`.

The fifth program, `explicit-exit`, is `dispatch_kind: "builtin", name: "exit"` — a
builtin, which F3 does not touch.

**This is the largest verified movement of the product gate available, and it is
smaller than any part of F3.**

### Slice 2 — F3 proper: real `define` + `call` as a FALLBACK

**Scope:** a non-recursive, effect-free, single-argument callee, emitted as a real
`define` + `call` **at the existing GAP sites**. The inliner stays on.

- Reuse `_emit_class_registry_ir`'s body-lowering shape (`LLVM.pm:780-831`) with value
  params instead of `(i8* %self)`, and a direct symbol instead of a vtable slot.
- Quote symbols (`@"main::f"`), no mangling.
- Reuse `_collect_straight_line_effect_chain` (`Context.pm:4459`) over the callee
  graph to **GAP on any storing callee** — that guard already exists and already
  fires, measured on two shapes.
- Zero producer change. Zero cross-repo risk.

**Acceptance:** unit tests in `t/bootstrap/ir/` over a hand-built two-graph MOP
asserting the emitted `.ll` contains `define`/`call` and `lli` prints the right value;
plus `subs.md` **F12 flips GAP → GREEN**; corpus floor **157 → 158**.

**Why fallback rather than disabling the inliner.** Disabling it strands ~320 lines
that landed three weeks ago — `_lower_inlined_effects_then_value`, the `{cache}` /
`_mut_read_memo` isolation (a hazard `cross_graph_id_keyed_cache_collisions` records
as SYSTEMIC), `af92594b`'s memoization, and 230 lines of tests that test nothing else
— and routes **9 already-green `subs` cases** through brand-new code. A fallback ships
exercised by F12 plus the unit tests. Disabling is risk transfer, not coverage;
it is a decision that should be *paid for by* evidence the call path is right, not the
thing you do to get that evidence.

### Slice 3 — recursion

`fib(10) == 55`, isolated. The single new question is the repr cycle, and per v1's
refutation it needs **both** a seed and a join-rule change (exclude the Bool condition
from `TernaryExpr`'s join), plus a decision about write-once stamping. Failing loudly
is guaranteed by Slice 0.

### Slice 4 — the memory contract, when something needs it

When a storing callee must actually lower. Priced honestly as cross-repo (13
`set_memory` sites, all producer-side; zero in chalk `lib/Chalk/IR/`), and framed as
**`_freeze_memory_reads($call)` mirroring `_is_array_mutating_call`** (`:2569-2575`),
not as a lattice.

The hazard is real and structurally confirmed — one `Subscript` node serves both the
pre-call and post-call read, and no emission strategy gives one node two values. Note
**`_lower_call_method` already emits real calls today**, so the direct-call path is
not the only exposure; a guard on one side of a boundary does not close a class.

**If the memory input is added, it MUST be appended trailing** — measured: trailing
passes the shape leg, prepending fails with "rooted wiring mismatch at return value."
The producer's own comment at `FromOptree.pm:2154` says memory *leads*, while the code
trails it. Pin the convention.

### Slice 5 — retire the inliner

Its own step, with its own proof, once the call path carries the 9 green `subs` cases.

---

## What outranks all of this for programs-unblocked

Recorded so this design is not read as the top priority it is not:

- **multi-argument callees** — `is($a,$b)`; the corpus names it as the t/op blocker
  (`subs.md:187`), and F3 as scoped leaves the one-argument ceiling in place
- ring histogram top three: **loop without a lowerable condition** (5 files),
  **producer emitted no `main::__main__`** (4 files), **`foreach` variants** (4 files)

## Verification

- Corpus gate, floor 157, three legs, coordinator-self-verified on committed HEAD.
  Never a subagent report.
- ir-block churn is zero for gate mechanics — the shape leg reads the loaded IR graph
  (`son-corpus-wide.t:154`), and `parse_l_verdict_from_ir` only distinguishes
  GREEN from GAP. **Re-verify empirically at implementation time**; it is the
  assumption that makes Slice 2 cheap.
- Cross-repo work (Slice 4 only) must be serialized — no producer version pin
  (`son-corpus-wide.t:17` resolves it as a live filesystem path).

## Out of scope

The operation type library (`runtime-mop-pilot`); narrowing the kill set; `@_`
modelling and multi-argument callees; Bool/aggregate/`Scalar` argument joins (their
join is `Scalar`, which exists but is not *representable* — the backend refuses
`repr=Scalar`); a separate `I_O` chain.
