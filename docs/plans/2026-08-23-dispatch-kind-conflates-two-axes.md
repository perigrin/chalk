# `dispatch_kind` conflates two axes and has no value for runtime-computed targets

**Date:** 2026-08-23
**Status:** FILED, COORDINATOR-VERIFIED. Not fixed. No miscompile — every
affected form GAPs today.
**Found by:** perigrin, reviewing the field while the F14/F15/F16 corpus `ir`
blocks were being written. Two objections, both measured below; the second
found a real gap, the first found a naming defect.

## What the field is

`Chalk::IR::Node::Call` carries `dispatch_kind` as a REQUIRED `:param`
(`lib/Chalk/IR/Node/Call.pm:10`). The backend branches on it at
`lib/Chalk/Target/LLVM/Context.pm:842-869`. Three values are ever emitted
(measured across the producer's `lib/`):

| value | backend path |
|---|---|
| `direct` | inline the resolved callee graph |
| `method` | vtable-slot dispatch through the class |
| `builtin` | emit the operation inline; `shift`/`pop`/`exit` only |

## Objection 1: `builtin` and `direct` are not distinguished by dispatch

Builtins are statically known — MORE so than a `direct` call, since they are
known before the program is read. If the field meant "how is the callee
found", they would be the same value.

They are not the same value because the backend does something different, but
the difference is not resolution. `shift`/`pop`/`exit` have NO callee graph
anywhere: there is no Perl body to inline, and the compiler itself is the
implementation. `exit` is not even value-producing — it terminates the block,
the shape `die` uses.

So the real axis under `builtin` vs `direct` is **is there a Perl body**, while
the field's name says **how is the callee found**. Two questions, one field.

This is a naming/modelling defect, not a correctness one. Nothing miscompiles.

## Objection 2: there is no value for a runtime-computed target — MEASURED

`$obj->$coderef` and `$obj->$name` resolve the callee at RUNTIME. Neither
`method` (no static name for a vtable slot) nor `direct` (no statically-known
callee) is true of them.

What the producer actually emits, measured (`SoN::FromOptree->translate`):

| form | emitted |
|---|---|
| `Thing::greet()` | `Call(dispatch_kind=direct, name=Thing::greet)` |
| `$o->greet` | `Call(dispatch_kind=method, name=greet)` |
| `shift @a` | `Call(dispatch_kind=builtin, name=shift)` |
| `$o->$m` (runtime name) | `Call(dispatch_kind=direct, name=unknown)` |
| `$o->$c` (coderef invocant) | `Call(dispatch_kind=direct, name=unknown)` |
| `$c->()` (plain coderef) | `Call(dispatch_kind=direct, name=unknown)` |

The three runtime-target forms are labelled `direct` — a claim that the callee
is statically known — while `name=unknown` says it is not. The node asserts
something false about itself.

**This does NOT miscompile today.** End-to-end through the backend, with the
package declared at file scope so no unrelated "undeclared class" GAP masks
the result (all five forms print `7` under perl):

| form | outcome |
|---|---|
| `Thing->greet` | GAP: `Call(method) reached LLVM backend with NO representation` |
| `Thing::greet()` | GAP: `direct call to 'Thing::greet' has no resolved callee` |
| `$c->()` | GAP: `direct call to 'unknown' has no resolved callee` |
| `Thing->$m` | GAP: `direct call to 'Thing' has no resolved callee` |
| `Thing->$c` | GAP: `direct call to 'Thing' has no resolved callee` |

GAP-not-miscompile holds. But note WHY it holds for the last two: the name
recorded is `Thing` — the INVOCANT, not the method — and the GAP fires because
no sub named `Thing` resolves. The refusal is accidental. It is not the
compiler recognising an unsupported dispatch form; it is a lookup failing on a
name that was never a callee. A future change that made invocant-named lookups
resolve would turn this GAP into a wrong answer with no other guard in place.

## Objection 3 (raised, and it does NOT hold)

`method($object)` — a plain sub call that happens to take an object — is
correctly `direct`. Nothing about passing an object makes a call a method
call, and the measurement confirms it: `Thing::greet($o)` emits
`dispatch_kind=direct, name=Thing::greet`. The field is right here.

## The underlying shape

`method` does not mean "written with `->`". It means **"the callee was
resolved statically"**, which is a claim about analysis success rather than
about source syntax — Perl allows the invocant's class to vary at runtime, so
even `$obj->greet` is only vtable-dispatchable when the class is known.

Two independent questions are being answered by one field:

1. **Where does the implementation come from** — a Perl body (inline it) or the
   compiler (emit it)? That is `builtin` vs everything else.
2. **Was the callee resolved statically** — yes (inline / vtable-slot) or no
   (needs an indirect call through a function pointer)? That is `direct` vs
   `method` vs the unrepresented fourth case.

A fourth value (`indirect`) would let the runtime-target forms state what they
are and GAP for the right reason. That is the minimum honest fix. Splitting the
two axes into two fields is the fuller one, and should not be done for its own
sake: nothing currently lowers an indirect call, so the value would exist only
to make the refusal accurate.

## Why this is not urgent

Nothing miscompiles, and no corpus case or `t/base` file exercises a
runtime-computed call target today. Filed so the accidental-GAP reasoning
above is written down BEFORE someone makes invocant-named lookups resolve —
that is the change that would convert this into a silent wrong answer.

Related: the CodeRef representation is separately unbuilt (`subs.md` F2/F3 are
`L: GAP` on exactly that), so an indirect call has no lowering to reach even
once the label is honest.
