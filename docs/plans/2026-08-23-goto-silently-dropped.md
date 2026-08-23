# `goto` is silently dropped — a third instance of the unbuilt-op class

**Date:** 2026-08-23
**Status:** FILED, COORDINATOR-VERIFIED. Not fixed.
**Found by:** measuring which `undef node_type` ops actually reach the generic
OpMap branch, while closing defect 2 of
`docs/plans/2026-08-22-two-producer-wrong-output-defects.md`.

## Symptom, measured

```perl
sub { my $x = 1; goto SKIP; $x = 999; SKIP: $x }
```

Producer output: `Start, Constant, Return`.

The `goto`, the statement it jumps over, and the label all vanish. No node, no
GAP, no stderr line. This is the same failure class as `write`: the compiler
proceeds confidently and emits a program that is missing part of its source.

Unlike `write`, this one produces a graph that looks entirely reasonable — a
constant and a return — so nothing downstream has any reason to object.

## Why it survived

`goto` is registered in `lib/SoN/FromOptree/OpMap.pm` with an `undef`
node_type and no SKIP flag. The generic branch builds nothing and returned
`'handled'`, which also makes the unknown-op `warn` unreachable, since that
only fires for UNREGISTERED ops.

As of perl5-son `8383dbe` the generic branch refuses ops on an explicit list
(`%UNBUILT_OP_GAP`), currently `enterwrite` and `leavewrite`. Adding `goto` to
that list is a two-line fix and would close this instance.

## The underlying defect is the `undef node_type` overload

`undef` currently means three unrelated things, and only the third is a bug:

| meaning | example | correct? |
|---|---|---|
| bookkeeping, no semantics | `nextstate`, `pushmark` | yes — SKIP says so |
| builds CONTROL, not a value | `and`, `cond_expr`, `poptry`, `return` | yes — but nothing says so |
| builds nothing, drops the construct | `enterwrite`, `goto` | **no** |

Measured: of the 56 registrations with `undef` node_type and no SKIP, BRANCH or
LOOP already covers 24 of them, and those translate correctly. Sixteen fall
through to the generic branch — `return`, `leavesub`, `leaveloop`, `last`,
`next`, `redo`, `leavetry`, `poptry`, `leaveeval`, `method_named`, `method`,
`die` all translate anyway because a mode-specific handler catches them
upstream. The remainder is where the drops live.

**A first attempt to refuse the whole shape (`undef` and not SKIP) broke
try/catch, loops and method dispatch** and was reverted. "undef node_type with
no SKIP flag" is a fact about how the table happens to be filled in, not a
semantic fact; treating it as one conflates control ops with dropped ones.

## The principled fix already exists, on the other side of the wire

`Chalk::IR::Value` (chalk `lib/Chalk/IR/Value.pm`) splits value-defining nodes
from control nodes by CLASS, and its own comment states the rule:

> A node either defines a value or it does not, and that is a STRUCTURAL fact
> about the node kind, not a property to be filled in.

It enumerates the same three-way overload, for the `type` field rather than for
`node_type`. The producer has no equivalent — `lib/SoN/IR/` is `Graph`, `Node`,
`NodeFactory`, `Stamp` and nothing else.

Mirroring that split (`SoN::IR::Value :isa(SoN::IR::Node)`) would collapse
`undef node_type` to one meaning and make `isa` the uniform predicate across the
wire, which is what "single IR, two implementations" is supposed to mean.

**RESOLVED, and BUILT — perl5-son `a9393a0`.** The producer mirrors chalk's
class hierarchy; the wire is unchanged.

The design question was: mirror the hierarchy, or put the value/control
distinction on the WIRE? Measurement settled it. The serialized form carries
`op` (`lib/SoN/IR/Serialize/JSON.pm:39`), and both sides already map that name
to a class independently — so value-ness is DERIVED identically at both ends
from data already present. A wire field would add a second source of truth for
a fact neither side has to be told, and would turn a producer/consumer
disagreement from a loud class-structure mismatch into a silent data mismatch.

The mirror was exactly determined rather than re-derived: both repos declare
the **same 88 node classes** with **identical intermediate parents** (`BinOp`,
`UnaryOp`, `Access`, `Aggregate`, `Regex`), and their 31 direct-parent classes
correspond one-to-one. So chalk's roster transfers verbatim — 19 intermediates
reparent and carry the other 57 leaves with them. Final split: 76 value, 12
control (`If ListAssign Loop MemStart Print Proj Region Return Start TryCatch
Unwind VarDecl`).

Additive only, verified before the edit: every `isa()` in producer `lib/` tests
a LEAF class, and no `ref() eq` tests a node class at all (only `'ARRAY'` and
`'B::SPECIAL'`), so inserting a base above the leaves changes no existing
dispatch. Producer suite 107 files / 570 tests PASS on a clean build; corpus
gate unchanged at `gate-green=215 behavior=215 shape=216 invariant=218
worklist=3`, exit 0, self-verified on committed HEAD.

**Scope caveat, and it HELD:** the Value split makes `undef` honest but does
NOT by itself catch this defect, and shipping it did not close `goto`. `goto`
builds no value AND no control, and only the second is the bug. Value-ness and
control-reachability are different axes — the same orthogonality
`Chalk::IR::Value`'s comment notes between value-ness and effects. The explicit
`%UNBUILT_OP_GAP` refusal list remains load-bearing after the split; a third
mechanism would be needed to make control-reachability structural the way
value-ness now is.

That the corpus gate did not move (215/215/216/218 before and after) is the
evidence: this was a structural change that bought no coverage, which is
exactly what was predicted. It makes a class of future bug expressible-and-
caught rather than fixing a present one.

## Unverified members of the same shape

Not measured, sharing the registration shape: `pushdefer`, `dump`, `once`,
`anywhile`, `formline`, `leavesublv`, `cmpchain_dup`, `argdefelem`. Each needs
a snippet run through the producer to tell a genuine drop from an op a handler
already owns. Cheap to do; none is likely to unblock a file, since nothing
currently compiles these constructs.

## Also observed

`sub { my $x = eval { 1 }; $x }` dies with `Stack underflow at
lib/SoN/FromOptree/StackSim.pm line 25`. Recorded because a prior session's
notes state that string was never OBSERVED in the ring; it reproduces here.
Note the path is `lib/SoN/FromOptree/StackSim.pm`, not `lib/SoN/StackSim.pm`.
Not investigated — and a die is at least loud, unlike the two defects above.
