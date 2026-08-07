# Design: real `define` + `call` — reordered after review

**Status:** design v2, awaiting review. Not a plan; no implementation.
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
