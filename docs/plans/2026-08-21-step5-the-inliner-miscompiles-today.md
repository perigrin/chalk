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
