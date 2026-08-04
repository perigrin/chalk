# Slice B — inliner effect-ordering (the coercion architecture's go/no-go gate)

ABOUTME: Build spec for Slice B, the go/no-go probe that proves-or-falsifies C5
ABOUTME: (effects stay in program order through an inlined loop+effect callee).

Date: 2026-07-23
Status: PLAN (capture) — pending assess -> refine -> chain-review -> execute
Parent: docs/plans/2026-07-22-coercion-architecture-slice-plan.md (Slice B section)
Decision record: git-zhi 019f88b4 (done) — recorded the operational criterion;
scheduled the BUILD behind Slice A's C2 proof (commit 79ec5e1b, landed).

## The claim this proves-or-falsifies

**C5 MONAD-SHAPED EFFECTS** — the control-chain effect threading keeps a spliced
loop+effect callee's stores/prints in PROGRAM ORDER when the callee is inlined at
a call site. This is the architecture's SELF-NAMED "biggest UNPROVEN mechanism"
and the whole slice program's pivot. If C5 holds, the modest coercion
architecture is earned incrementally. If C5 is structurally impossible, the
architecture is falsified at its own weakest point, cheaply, with one slice.

## The gap, verified on head (branch phase5-capstone, 2026-07-23)

`_lower_call_direct` (lib/Chalk/Target/LLVM/Context.pm:4299) inlines ONLY the
callee's return-VALUE subgraph:

```perl
my $value = $returns[0]->inputs->[-1];   # the Return node's value input
...
return $self->lower_value($value);        # lowers ONLY that data subgraph
```

It never walks the callee's `control_in` effect chain. So a callee that performs
an effect and then returns a value gets its effect SILENTLY DROPPED at inline
time. That is a silent miscompile-class today, masked only because no corpus case
exercises an effectful inlined callee. The GAP-not-miscompile invariant is
currently VIOLATED for this shape (silent wrong answer, not a loud GAP).

### Verified end-to-end (assess, 2026-07-23) — the RED case IS constructible

For `sub f { print "x"; 2 } my $r = f(); $r` (corpus-wrapped), B::SoN emits the
effectful callee with its effect ON the control chain, and the loader preserves it:

```
main::f graph:  { op:Print, control_in:Start } <- { op:Return, control_in:Print, inputs:[Constant(2)] }
```

Lowering the loaded graph through `Chalk::Target::LLVM->lower` succeeds and emits
ONLY the value (`add i64 0, 2` + a printf of it), dropping the callee's `print "x"`:
`lli` prints `Int:2`; perl prints `xInt:2`. The silent drop reproduces. So the
corpus behavior leg (lli vs perl oracle) classifies it BUG — a RED-first corpus
case works as designed. **No producer prerequisite blocks the print/store shapes.**

**Producer constraint (must respect in examples):** `push @a` in a callee is a
PRODUCER GAP — B::SoN emits `skipped: GAP: push (array length mutation) not yet
lowered`. It is NOT a Slice B shape. The loop-EFFECT shape must use element store
`$a[$i] = ...` (verified producible: `sub storer { my @a=(0,0,0); for my $i (0..2)
{ $a[$i]=$i } $a[1] }` → Return chain rooted at the loop-exit Region). Verified
producible print shapes: `sub prpr { print "a"; print "b"; 7 }` → chain
`Print("b") -> Print("a") -> Start` (program order encoded);
`sub printer { for my $i (1..2) { print "x" } 5 }` → Region-rooted chain.

## Commit 1 — convert the silent effect-drop to a LOUD GAP (small, safe, standalone)

In `_lower_call_direct`, after resolving the callee's single Return, detect
whether that Return has effects on its control chain and, if so, `die` with a GAP
message instead of silently dropping them.

- Detection (SIMPLIFIED per assess — one comparison, NO chain walk): **GAP unless
  the callee `Return.control_in` is undef or a `Start` node.** A pure callee's
  Return.control_in is `Start` (the producer puts pure pad/data work OFF the
  control chain); an effectful callee's is a `Print`/`Assign`/store or a
  loop/branch `Region`. Measured across the entire green inline-call population —
  `subs.md` F1, F1v, F5, F6, F8 and `control-flow.md` T5 all have
  `control_in = Start`, as do all probed pure-but-nontrivial shapes (ternary,
  branchy pad-rebind, local-array, multi-statement). So the Start-check has ZERO
  false positives and cannot regress a green case. A Region-rooted callee (loop/
  branch) is never green today anyway — its exit-Phi return value dies opaquely in
  `lower_value` — so GAPping it converts an opaque die into a clean GAP.
  `Return.control_in` is a real reader (`Node.pm` `field $control_in :reader`).
- Message: `GAP: direct call to '$name': callee has effect(s) on its control
  chain (print/store/...) that inlining does not yet thread in program order.`
- Standalone value: turns a silent-miscompile class into a loud GAP. Lands whether
  or not Commit 2 ever does. This is the plan's guaranteed rung.

### Commit 1 gate
- RED-first corpus case: an effectful-callee inline (`sub f { print "x"; 2 } ...
  f()`) that is a silent wrong-answer / drop BEFORE the GAP, and a LOUD GAP AFTER.
  The corpus's gap-declared leg absorbs it (worklist behaves as designed).
- The full corpus triple contract holds; floor PINNED at implementation-measured
  value (currently 153 — do NOT hardcode; re-measure). No previously-green case
  regresses.
- GAP-not-miscompile invariant RESTORED for the effectful-callee shape.

## Commit 2 (SPLIT per assess) — 2-print now, loop-store parked

The parent plan bundled all effect ordering into one Commit 2. Assess showed the
straight-line print case needs NO memory-SSA at all, while the loop-store case
drags in the whole memory scan + elaboration machinery. Splitting them isolates
the mechanism C5 actually doubts (cross-graph program ordering) from the
orthogonal memory-SSA work.

### Commit 2-print — straight-line effect ordering across graphs (the real C5 probe)

A print-only callee chain (`Print -> ... -> Start`) contains no `Assign`, no
`MemStart`, no `Region`, so it needs NO memory-SSA. `process_control_node`
(Context.pm) already dispatches `Print` via `%STATEMENT_EFFECT_OPS`. So:

- Collect the callee's control chain from its Return via `control_in`.
- GAP if any node on that chain is a `Region`/`Loop`/`If`/`Assign` (that is the
  parked loop-store case, not this commit).
- Else reverse-drive the chain through `process_control_node` inside the arg-bind
  frame, splicing the callee's prints into the caller's chain in program order.

This proves C5's load-bearing question: an inlined callee's effects land in
program order relative to the caller's, across a graph boundary. The top-level
mechanism already orders two prints (statements.md two-ordered-prints is GREEN) —
Commit 2-print proves it survives the graph splice.

**Hazards that hit even the print-only case (assess found; the spec's original
memory-SSA hazard is the SMALLEST of these):**

1. **Cross-graph string-id cache collision — LOAD-BEARING.** `lower_value` caches
   by STRING id (`$self->{cache}{$id}`, Context.pm:341); the code documents that
   caller/callee ids collide because each graph numbers `Op#N` from its own
   factory (Context.pm:315-316 — the very reason `_arg_bind` is refaddr-keyed).
   Statement-effect nodes get counter ids (`NodeFactory.pm` `"${op}#${counter}"`),
   so a callee `Print#1` colliding with a caller `Print#1` is served the cached
   ref and SILENTLY SKIPPED — re-introducing the exact bug Slice B closes. Commit
   2 MUST key effect emission per-inline (refaddr) or namespace the cache.
2. **Same-callee-inlined-twice.** Side-effecting ops STAY cached — "they execute
   once at their control position; re-lowering would double the effect"
   (Context.pm:339-340). Two call sites to one effectful callee share ONE Print
   object; the second inline's effect is dropped by cache design. Commit 2's gate
   must include a two-call-site variant OR the doc fences it (GAP on second inline
   of an effectful callee).
3. **Bidirectional flag staleness.** Localizing `_branch_guarded_store` matters
   BOTH directions — an unrestored callee scan also poisons the caller's post-call
   lowering. (Relevant to the parked loop-store case, noted here for completeness.)

### Commit 2-loop-store — PARKED as a separate slice (the heavy memory-SSA rung)

A callee with a loop/branch effect (Region-rooted chain, element store `$a[$i]=`)
requires, beyond hazards 1-2: localizing `_scan_memory_shape`'s cached
`_branch_guarded_store` (Context.pm:2474) and re-running `_find_memstart` /
`_freeze_memory_reads` per-callee-subgraph; AND a per-callee elaboration plan —
`_process_if_node` consumes phi records precomputed from the TOP Return only
(ElaboratedContext.pm; plans built at LLVM.pm:56-57), so a callee with an internal
If/loop has ZERO records in the caller's ctx. The precedent for lowering a second
graph is the method-body path (fresh Dominators + Elaborate + ctx per body,
LLVM.pm:766-783) — genuinely new machinery, not a flag localization. This is a
SEPARATE slice with its own budget; it is NOT required to discharge the C5
ordering question (Commit 2-print does that).

**C5-as-worded caveat:** the parent plan words C5 over the "loop+effect" shape.
Commit 2-print proves the ordering MECHANISM cross-graph; the loop adds orthogonal
memory-SSA. Either restate C5 (mechanism proven by print; loop is memory-SSA
re-entrancy, not an ordering question) or accept that only the parked loop-store
slice fully discharges C5-as-literally-worded. Recommend the restatement — the
model half is already proven (see the go/no-go criterion below).

### C4 rider — needs NEW corpus machinery, and is near-tautological

Slice B's C4 claim (coercions pure/cacheable BECAUSE effects quarantined to the
control chain) CANNOT be observed by behavior output alone: `lli == perl` cannot
see the NON-emission of dead pure code. A shape assertion (dead pure callee
computation ABSENT from the emitted `.ll`) is required to gate C4.

**Scope assess surfaced:** the corpus has NO per-case `.ll` assertion facility.
`_split_into_cases` knows only `perl`/`chalk`, `behavior`, `ir` fence types
(MdtestCorpus.pm:751-760); the `ir` block asserts the GRAPH (presence/subset — it
cannot assert ABSENCE and never sees the `.ll`), and the libperl guard
(MdtestCorpus.pm:2310-2336) is a hardcoded whole-suite regex, not a reusable
per-case facility. So the C4 assertion needs NEW machinery (a new fence type +
parse + runner check, or a dedicated one-off `.t`) — added scope to name and cost.
Honest framing: `lower_value` is demand-driven from the Return value + control
chain, so dead pure callee code is never lowered BY CONSTRUCTION — the C4
assertion is a cheap REGRESSION LOCK, not a discriminating proof. Do not oversell
it as "proving C4."

### Commit 2-print gate
- Ordered-print callee inline emits effects in PROGRAM ORDER: behavior
  `lli == perl` for a case whose output depends on ordering (callee prints, caller
  prints — order must match perl). Two-call-site variant included (hazard 2) or
  fenced.
- Corpus triple contract holds, floor re-pinned upward if the case greens.
- No existing inline-call or effect case regressed (per-inline effect keying did
  not break single-graph effect caching).
- (If the C4 shape assertion lands with this commit, dead pure callee computation
  absent from the `.ll`; else C4 is explicitly deferred with the loop-store slice.)

## The go/no-go criterion (recorded verbatim + sharpened per assess)

**Recorded verbatim (from decision record 019f88b4 + parent plan — do NOT edit):**
Slice B is FALSIFIED (C5 dead -> architecture dead) ONLY IF the control-chain
model CANNOT EXPRESS a spliced loop+effect body's store/print ordering within
bounded effort — a structural impossibility. A dropped or reordered store on the
FIRST attempt is a BUG to debug (bounded effort, ~2 sessions), NOT a STOP signal.
Third honest outcome: Commit 1 (loud GAP) lands, Commit 2 (ordered lowering)
DEFERRED with a follow-up -> neither proven nor falsified; park it.

**Sharpened operational rule (assess found the verbatim criterion too soft — its
"structural impossibility" is now UNOBSERVABLE because C5's model half is already
proven by inspection, so it authorizes unbounded grinding):**

1. **C5's model half is PROVEN by inspection.** The callee's effect ordering IS
   fully encoded in the IR the producer emits and the loader preserves (measured:
   `prpr` chain `Print("b") -> Print("a") -> Start` in program order; loop shapes
   Region-rooted and reachable), and the identical chain mechanism already lowers
   in program order at top level (statements.md two-ordered-prints, GREEN). The
   residual risk is BACKEND RE-ENTRANCY only, not model expressibility.
2. **FALSIFIED is now a static, checkable condition:** an effect node of the
   callee that is NOT reachable from the callee Return via `control_in` +
   control-flow inputs (its order is unrecoverable FROM THE GRAPH). None found in
   the probed shapes; if one is ever found, THAT falsifies the model. Anything
   reachable-but-mis-emitted is a backend bug, not a falsification.
3. **Bounded-effort line is gate-shaped, per rung:** if Commit 2-print is not
   GREEN with the floor held after ~2 sessions -> PARK (the third outcome),
   explicitly NOT "keep debugging." The loop-store slice gets its OWN separately
   budgeted 2-session window. No single mechanism absorbs unbounded effort.

## Scope fence

- Does NOT build the Chalk::Meta::Type registry (deferred behind B-holds AND N>=3).
- Does NOT re-point any production call-site.
- Does NOT touch Slice A's divide Coerce bridge.
- chalk-only backend change (Context.pm + LLVM.pm). NO perl5-son producer edit
  required — assess VERIFIED the producer already emits the effectful callee with
  its effect on the control chain (`Return.control_in -> Print -> Start`), the
  loader preserves it, and the silent drop reproduces end-to-end (lli `Int:2` vs
  perl `xInt:2`). The only producer constraint: `push @a` is a producer GAP, so
  the loop-effect shape must use element store `$a[$i]=...` (parked slice), not
  push.

## Mandatory gate (unchanged from Slice A)

The corpus gate t/bootstrap/corpus/son-corpus-wide.t triple contract (behavior
lli==perl + shape rooted-subset + TypedInvariant), floor PINNED at
implementation-measured value (NOT hardcoded), self-verified BY THE COORDINATOR
(not a subagent self-report), on committed HEAD, run with
$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib -It/lib. RED-first corpus
case required. GAP-not-miscompile invariant enforced after Commit 1.

## OUTCOME (2026-08-01) — PARTIAL GREEN. Read this before citing Slice B.

**Slice B did NOT fully discharge its own charter. It is PARTIAL, not green.**
Milestone `coercion-slice-b` completed with all its issues done, but the
milestone scope was deliberately narrower than this document's title
("inliner on a loop+effect callee"). Do not read "milestone complete" as
"Slice B green."

### What IS proven
- **C5 for the STRAIGHT-LINE PRINT shape only.** An inlined callee whose
  `Return.control_in` chain is `Print -> ... -> Start` now has its effects
  threaded in PROGRAM ORDER at the call site (`_lower_call_direct` ->
  `_collect_straight_line_effect_chain` + `_lower_inlined_effects_then_value`).
  Corpus: subs.md F9 (ordered print), F10 (cross-graph cache-collision proof --
  caller and callee Print ids DO collide in the real B::SoN graph, measured),
  F11 (two-call-site double-emission, GREEN not fenced). Gate 153 -> 156.
- **The CALLEE-SIDE silent effect-drop miscompile class is CLOSED** (Commit 1):
  both of the *callee's* effect-attachment paths -- `Return.control_in` AND
  `Return.inputs[1..]` (the trailing void statement-effect) -- now GAP loudly
  instead of dropping.
  **[RE-SCOPED 2026-08-03. This originally read "the silent effect-drop
  miscompile class is CLOSED", which was false as stated.** Commit 1's guard
  inspects only the CALLEE's attachment paths; the CALLER-side path -- whether
  the `Call` node is itself on the caller's control chain, and whether it still
  exists -- was unguarded. F4 (`sub f { print "x"; 2 } my $r = f(); 3`)
  reproduced live on HEAD with NO GAP: the producer pinned a Call's `control_in`
  only `if $void`, so a non-void call was unreachable from Return and the
  reachability walk dropped it entirely -- chalk printed nothing where perl
  prints `x`. The caller side was closed later by perl5-son R1.0 (commit
  40d8f8b, milestone `effect-chain-fix`), which pins every Call unconditionally.
  In one line: this closed the callee half of the effect-drop class, not the
  class. See `docs/plans/2026-08-03-effect-chain-followups.md` Part C.]
- **Two latent cross-graph collision hazards fixed**, both from the same root
  cause (id-keyed tables shared across graphs that number nodes from separate
  factories): `{cache}` (Commit 2-print) and `_mut_read_memo` (zhi 019fbe27, a
  REACHABLE stale-value miscompile, RED-proven `Int:3` vs correct `Int:2`).

### What is NOT proven (and therefore what the decision gate still lacks)
- **C5 for the LOOP+EFFECT shape -- this document title's actual subject --
  is PARKED, not proven.** See "Commit 2-loop-store" above. It needs the
  memory-SSA re-entrancy work (localizing `_scan_memory_shape`'s cached
  `_branch_guarded_store`, per-callee elaboration plans).
- **C4 was never built.** The shape-block assertion (dead pure callee code
  ABSENT from the emitted `.ll`) needs new corpus machinery and is
  near-tautological as specified. Slice B proves C5 only, exactly as this
  document's own C4-rider section warned.

### Consequence for the registry decision gate
`2026-07-22-coercion-architecture-slice-plan.md:147-153` requires "Slice B
green WITH its C4 shape-block assertion (C5 + C4 proven)" plus N>=3 real
coercion insertions. **NONE of those three conditions is met** (C5 partial, C4
absent, N=1). `Chalk::Meta::Type` therefore remains DEFERRED. The architecture
is NOT falsified -- the no-go condition (a dropped or reordered store) did not
occur -- but it is NOT earned either.

### Load-bearing precondition on the parked work
`_lower_inlined_effects_then_value` documents a DOUBLE-LOWER invariant: the
fresh `{cache}` is scoped to the effect drive, so a value node also referenced
by an effect is lowered twice. That is safe ONLY because the Print-only guard
admits only pure-idempotent or no-emit-PadAccess value nodes. **Widening that
guard (i.e. the parked loop-store slice) MUST re-establish the invariant or it
silently reintroduces a double-effect miscompile.** An adversarial review
constructed the miscompiling shape; it is gated closed today only by the
Print-only restriction.

### Cross-roadmap note (why the PARK matters more than its label suggests)
The bare-file protocol's third, previously unbudgeted line item is INTER-GRAPH
CALLS: "a real file = `__PROGRAM__` + N sub graphs it calls; the current inliner
INLINES ONLY, SILENTLY DROPS effectful callee bodies." Slice B retired the
silent-drop half of that risk. But real lib/ methods contain loops and stores,
not straight-line prints -- so **Commit 2-loop-store sits on the critical path
to lib/ self-hosting (the project North Star), not merely on the coercion
registry's path.** Budget it accordingly.
