# `dispatch_kind` conflates two axes and has no value for runtime-computed targets

**Date:** 2026-08-23
**Status:** FILED, COORDINATOR-VERIFIED. Not fixed. No miscompile — every
affected form GAPs today.
**Found by:** perigrin, reviewing the field while the F14/F15/F16 corpus `ir`
blocks were being written. Three objections, all measured below: two held, one
did not, and following them up surfaced a SECOND and more valuable defect that
is not about this field at all (see "Two defects, not one").

**Read the measurement table before the argument.** An earlier revision of this
document claimed every call form fails identically; that was a probe artifact
(`package=main` excluded the callee class from the wire). The plain named call
resolves and types correctly. The corrected numbers are below.

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

**This does NOT miscompile today.** Every form GAPs. But the CAUSES are not
what the dispatch story predicts, and separating them is the point of this
section — measured by inspecting the loaded graph rather than the GAP text:

| form | dispatch_kind | name | Call repr | callee graph |
|---|---|---|---|---|
| `Thing::greet()` | `direct` | `Thing::greet` | **Int** | **resolved** |
| `Thing->greet` | `method` | `greet` | UNDEF | unresolved |
| `$c->()` | `direct` | `unknown` | UNDEF | unresolved |
| `Thing->$m` | `direct` | `Thing` | UNDEF | unresolved |
| `Thing->$c` | `direct` | `Thing` | UNDEF | unresolved |

**The plain named call WORKS.** It resolves its callee and types as `Int`. So
this is not "every call form is broken", and an earlier reading of these
measurements that said so was an artifact of running the probe with
`package=main`, which excluded `Thing` from the wire entirely and made all five
fail identically for a reason unrelated to any of them.

### The method case is a CLASSIFICATION mismatch, not a dispatch failure

`Thing->greet` is the interesting one: the class IS in the wire and its body IS
loaded as a graph. What the wire says is:

    Thing: methods=[] subs=[greet]

`greet` is classified as a **sub**, not a method. The call site asks for a
METHOD named `greet` on class `Thing` and finds an empty method list — so the
callee is unresolved, so the Call carries no return type, so `_require_repr`
(`lib/Chalk/Target/LLVM.pm:80`) GAPs with "reached LLVM backend with NO
representation", whose own comment says that is "always a TypeInference gap".

The producer is not wrong to classify it that way. `sub greet { 7 }` in a plain
package genuinely IS a sub; perl does not distinguish, and the same body is
reachable as `Thing::greet($o)` and as `$o->greet`. That is the same fact that
makes objection 3 below fail. The mismatch is that the CALL SITE commits to one
of the two spellings while the DECLARATION is recorded under the other, and
nothing reconciles them.

So the method form's GAP is about the graph not being classified in a way the
call site can use — not about `dispatch_kind` being the wrong label. The label
is right; the lookup it drives has nowhere to land.

### The runtime-target forms GAP for the wrong reason

For `Thing->$m` and `Thing->$c` the name recorded is `Thing` — the INVOCANT,
not the method — and the GAP fires because no sub named `Thing` resolves. That
refusal is accidental. It is not the compiler recognising an unsupported
dispatch form; it is a lookup failing on a name that was never a callee. A
change that made invocant-named lookups resolve would turn this GAP into a
wrong answer with no other guard in place. That is the reason to write this
down now rather than when it bites.

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

## Two defects, not one — and only the first is about this field

Separating them, because they have different owners and different fixes:

1. **`dispatch_kind` has no value for a runtime-computed target** (this
   document's subject). Fix: a fourth value, `indirect`. Small, and it only
   makes the refusal accurate.

2. **A plain-package sub is classified as a sub and looked up as a method.**
   `Thing: methods=[] subs=[greet]` while the call site asks for method
   `greet`. This is NOT a dispatch-labelling problem — it is the graph not
   being classified in a way the call site can use, which is where the Call
   semantics work ran aground. Fix: reconcile the two spellings, either by
   recording a plain-package sub under both, or by having method lookup fall
   back to the sub table (which is what perl does).

Defect 2 is the one that blocks `Thing->greet`, an ordinary form, and is
therefore the more valuable of the two. It is filed here because it was found
while measuring this field, not because the field causes it.

## Why this is not urgent

Nothing miscompiles. No corpus case or `t/base` file exercises a
runtime-computed call target today, and the method form GAPs loudly rather
than answering wrongly. Filed so the accidental-GAP reasoning above is written
down BEFORE someone makes invocant-named lookups resolve — that is the change
that would convert defect 1 into a silent wrong answer.

Related: the CodeRef representation is separately unbuilt (`subs.md` F2/F3 are
`L: GAP` on exactly that), so an indirect call has no lowering to reach even
once the label is honest.
