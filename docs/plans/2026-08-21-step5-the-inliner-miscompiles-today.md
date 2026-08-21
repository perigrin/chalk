# Step 5 scoped: the inliner is not a premature optimization, it is a LIVE MISCOMPILE

**Date:** 2026-08-21
**Status:** MEASURED, not built. chalk `259a5e94`, perl5-son `dfe02e3`.
**Supersedes** the framing in `2026-08-20-sub-metadata-is-the-missing-channel.md`
step 5, which treated retiring the inliner as cleanup.

## The finding

Measured while scoping, on a shape nothing in the corpus covers:

```perl
sub f { my $n = shift; $n * 2 }
my $a = f(1);
my $b = f(2);
print "$a $b ", $a+$b, "\n";
```

    perl:  2 4 6
    chalk: 2 2 4

**`f(2)` returns 2.** The second call reuses the first call's inlined result.
Silent — no GAP, no warning, wrong number.

**PRE-EXISTING**, verified rather than assumed: reproduced at chalk `27e72ba7`
with a matched pre-`ArgsSource` producer (`95ebe79`), and again at `51447ae3`.
Not introduced by the step 3/4 work.

## Why this reframes step 5

The plan justified retiring the inliner on *principle* — "an optimization that
is load-bearing is infrastructure wearing the wrong label" — and on coverage,
that the green `subs` cases test substitution rather than calls. Both true, and
both weaker than what is actually here.

The inliner does not merely hide whether calls work. **It computes wrong answers
today, on ordinary code.** Two calls to the same sub with different arguments is
not an exotic shape.

That also retires the "0 programs unblocked" objection that de-prioritised F3 in
August. The question is no longer what retiring the inliner *enables*; it is
what leaving it in place *breaks*.

## What blocks each shape, measured

| shape | today |
|---|---|
| no-arg `f()` | works |
| one-arg `f($x)` | works |
| **two call sites** | **MISCOMPILES (2 2 4 vs 2 4 6)** |
| two-arg `f($a,$b)` | GAPs — arity |
| recursion (`fib`) | GAPs — **repr, not calls** |

## `fib` is a TYPING cycle, not a call-emission gap

The F3 v1 refutation said so and it still holds. Node reprs in `main::fib`:

    ArgsSource   UNDEF
    Call         Int      <- the outer call, stamped from its arg
    NumLt        Bool
    Subtract     Int
    Call         UNDEF    <- fib($n-1)
    Call         UNDEF    <- fib($n-2)
    Add          UNDEF
    TernaryExpr  UNDEF

`_resolve_direct_calls` stamps a Call's repr from its callee's Return value. For
a self-recursive sub that Return depends on those very Calls — a cycle the
fixpoint cannot break, so it bails and the consumers never type.

**Consequence for scoping:** emitting `define`+`call` does NOT unblock recursion
by itself. The repr cycle needs a seed (or a widening rule), and that is a
separate piece of work from call emission. Do not bundle them; do not claim
`fib` as step 5's deliverable without doing it.

## What already exists

- **the sub-define emitter** — built in 1c, gated behind `CHALK_EMIT_SUB_DEFINES`
  because emitting while the inliner is live duplicates bodies
- **real `define`/`call` for METHODS** — `_emit_class_registry_ir`,
  `_lower_call_method`; a direct call is the simpler case
- **`main` is skipped at registry population** (`LLVM.pm:352`), so main's subs
  never reach the emitter even with the flag on
- **the callee metaobject on the Call** — step 1d, `target->graph`
- **`uses_args`** — step 1a/1b, the callee property the calling convention needs

## Ordering this implies

1. **Pin the miscompile as a corpus case first.** It is invisible to the gate
   today; 214 cases and none covers two call sites of one sub. Landing the fix
   without the case leaves nothing to prevent regression.
2. **Emit `define` for main's subs** — un-skip `main`, drop the env gate.
3. **Route direct calls through `call`**, inliner off. This is where the nine
   green `subs` cases start testing call semantics instead of substitution.
4. **Then** the arity/`@_` work (step 3's params-by-default) and the repr cycle
   (recursion), each on its own.

## What this does NOT establish

- No claim that `define`+`call` is small. `_emit_class_registry_ir` is ~270
  lines coupled to `(i8* %self)`, vtables, and the class registry; the plan's
  "measure what is genuinely reusable" caveat stands and is not answered here.
- The miscompile's exact mechanism is not traced. It is consistent with a
  memoization keyed on the callee rather than the call site, and
  `_lower_call_direct` does memoize — but I have not confirmed which cache.
- Only ONE miscompiling shape is measured. There may be more in the same family
  (same sub, same args, different effects; nested calls) and they are not swept.

---

# The sweep (2026-08-21)

Eleven shapes, varying one dimension at a time. **4 MISCOMPILE, 6 ok, 1 GAP.**

| shape | result |
|---|---|
| 1 call | ok |
| **2 calls, different args** | **MISCOMPILE** `6` -> `4` |
| **3 calls, different args** | **MISCOMPILE** `12` -> `6` |
| 2 calls, SAME arg | ok |
| 2 calls, no-arg callee | ok |
| 2 calls via `$_[0]` | ok |
| 2 calls, variable args | GAP |
| 2 calls, effectful callee | ok (`c1c2`) |
| **2 calls, separate statements** | **MISCOMPILE** `2 4` -> `2 2` |
| `f(1) + g(2)` (two callees) | ok |
| **`f(f(1))` nested** | **MISCOMPILE** `4` -> `2` |

## The shape of the bug

It needs **two or more calls to the SAME callee with DIFFERENT arguments**.
Not expression-vs-statement (both miscompile), not effects (an effectful callee
is fine), not call count beyond two. Two different callees are fine. Nesting a
call in its own argument is the same bug reached differently.

`f(3)+f(3)` is "ok" only because the answer coincides — the second call still
reuses the first's value, which happens to be right when the arguments match.
That is a shape whose CORRECT answer hides the defect, and it is why a corpus
case must use different arguments.

## Mechanism: the value cache, confirmed by construction

Not what I first predicted. My hypothesis was an ID collision — the callee's
`shift` node is `Call#2` and a caller Call is also `Call#2`, and the memo
`$self->{cache}{$node->id}` is keyed by STRING id across graphs. Measured: the
`$_[0]` form collides identically (`collidingCalleeIds=[3]`) and does NOT
miscompile, so the collision alone is not sufficient.

The discriminator is `%MUTABLE_READ_OPS` (`Context.pm:626`). `Subscript` is in
it and therefore **bypasses the value cache**, re-lowering at every consumption.
`Call` is not, so it serves a stale cached value from the other call site.

Confirmed by probe: adding `Call` to `%MUTABLE_READ_OPS` yields `2 4 6`,
matching perl.

**That probe is a diagnosis, not the fix** — it would disable legitimate CSE for
every Call. The real fix is that a real `call` has no shared cache to collide
in, which is what step 5 does. Recorded because it explains why `$_[0]` survives
(accident of node kind, not correctness) and why a fix must not be validated
against the `$_[0]` form.

## Consequences for the ordering

- The corpus case MUST use two calls with DIFFERENT arguments. `f(3)+f(3)` and
  the `$_[0]` form both pass today and would pin nothing.
- The nested `f(f(1))` shape is worth its own case: same root, different reach,
  and an argument-binding fix could plausibly close one and not the other.
- `2 calls, variable args` GAPs rather than miscompiling, so the family is
  partly masked by an unrelated refusal. If that GAP is lifted first, the
  miscompile surface grows.

---

# Why the fix is NOT a staleness-bucket change (2026-08-21)

Recorded because it is the first thing to reach for, and I reached for it.

perigrin's framing: the inlining/cacheability decision rests on several factors,
and opaque/transparent and pure/effectful are two of them. Correct -- I had
flattened them into one axis.

`Chalk::IR::Node` already separates three type properties:

| property | question | what lives there |
|---|---|---|
| `is_fixed` | must this execute at its control position? | **effects** |
| `staleness_kind` | can a cached value go stale? | **values** |
| `identity_kind` | own node per occurrence, or shared? | `per_call` / `hash_consed` |

`Call` answers `is_fixed = true` and `staleness_kind = opaque`. **Both are
correct.** `opaque` means "a fixed SSA value at a single program point", which is
exactly what a call is.

## `transparent` is not the answer for an effectful sub

The middle bucket is TRANSPARENCY, not purity -- the doc on
`staleness_kind` says so, and its membership confirms it: `Divide`, `And`,
`NumEq`, `Length`, `Defined`, all pure functions of their inputs. It means "my
value is stale exactly when an input's is -- ask my inputs", not "I have
effects".

For `sub f { print "x"; 7 }` the return value's staleness has no relationship to
its arguments' staleness. The print is a control-position question, which
`is_fixed` already answers. Marking that Call `transparent` would ask the wrong
question AND still cache wrongly across call sites with equal arguments.

## The missing dimension is not a node property

Cacheability needs one more input, and no bucket can express it: **which
arguments were bound when the cached value was computed.** That is
per-CALL-SITE context.

The cache key is `$node->id`. For a real call that suffices -- argument binding
lives in the call instruction and the callee is lowered once. Under inlining the
same node id spans multiple bindings, so the key is missing a dimension the node
model has no way to supply.

## Consequence

The inliner is not premature in the ordinary sense of correct-but-early. It
**falsifies a premise the IR states as a type property**, silently: `Call` says
"one program point", inlining re-lowers it at many.

So the fix is structural rather than a re-labelling. A real `call` restores
`opaque`'s premise by construction -- arguments become parameters, the callee
lowers once, and nothing needs a new bucket.

---

# It is not inlining the GRAPH -- only the effects (2026-08-21)

perigrin, reading the sweep: "it doesn't sound like we are actually inlining the
graph ... we're just inlining the return value after having cached it once."

Correct, and sharper than the framing above. Measured on `f(1)` then `f(2)`:

    mul emitted: 1

**One `mul` for two calls.** The callee's body is not substituted twice. It is
lowered once and the resulting SSA ref handed to the second site.

The effectful variant splits the mechanism cleanly. For
`sub f { my $n=shift; print "c"; $n*2 }` called twice:

    mul emitted: 1   print emitted: 3   (2 callee prints + 1 caller print)

So the two halves take DIFFERENT paths, and only one of them is per-site:

- the **effect chain** is re-driven at each call site -- correct, both prints fire
- the **value** is lowered through the shared `{cache}` -- wrong, computed once

`_lower_call_direct` (`Context.pm:5871-5879`) localises `_arg_bind` per site and
drives the effect chain per site, then calls
`_lower_inlined_effects_then_value(\@effect_chain, $value)`. That last call
lowers `$value` through `$self->{cache}`, so the callee's `Multiply` node is
cached on the first site and served on the second -- with the first site's
argument baked in.

## Why this matters for the fix

"Inlining is wrong here" and "inlining is not what is happening" are different
claims, and the second is the true one. The pass does not duplicate a body; it
memoises a computation across contexts that disagree about what its inputs are.

That is why the effect chain looks healthy while the value is wrong, why an
effectful callee passes the naive sweep (its visible output comes from the
effects, which ARE per-site), and why `f(3)+f(3)` passes -- with equal arguments
the single cached computation happens to be the right answer for both.

It also means "turn the inliner off" is not removing a duplication pass. There
is no duplication to remove. What is there is a value cache doing cross-context
memoisation, and a real `call` replaces it with a call instruction rather than
undoing a substitution.

---

# CORRECTION: fib's cycle is a fixpoint that bails, not a missing subsystem

perigrin: we added type-lattice lookups recently and were working toward a fully
typed IR -- check that. Right, and I had overstated the gap.

**What I said above is too broad.** "TypeInference does not run on this path" is
true only of the Earley semiring class `Chalk::Grammar::Perl::TypeInference`.
The type LATTICE is very much on the B::SoN path: `Serialize/JSON.pm:16` imports
`TypeLibrary`, and uses it at four sites -- `_join_repr` (merge widening,
derived from the lattice rather than the old `%_REPR_RANK` table),
`operand_repr_for_ir_op`, `accepts_operand_repr`, and `is_subtype`.

**And fib is closer than I scoped it.** Measured on its Return value:

    TernaryExpr  repr=UNDEF
      arm NumLt  repr=Bool     <- the condition
      arm Call   repr=Int      <- the BASE CASE, already typed
      arm Add    repr=UNDEF    <- the recursive arm

One arm is already `Int`, stamped from the argument. The cycle is breakable with
the machinery that exists: join over the arms that ARE known and `Int` falls out.
The fixpoint gives up when any input is UNDEF instead of joining over the rest.

So the correct filing is NOT "the loader needs a type-inference subsystem it
lacks". It is: **`_join_repr`'s callers bail on an UNDEF input rather than
joining the known ones.** That is a much smaller change, in one function's
callers, and it is still independent of call emission.

Kept out of step 5 anyway, for the reason already stated: it is a loader-fixpoint
change with its own verification, and bundling it means neither half gets proven
on its own. But the estimate was wrong and the wrong estimate is what would have
made it look unaffordable later.
