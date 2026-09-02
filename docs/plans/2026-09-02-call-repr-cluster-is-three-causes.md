docs(ir): the "Call with no repr" cluster is THREE causes, and my hypothesis was wrong

I grouped 8-10 corpus gaps as one root cause -- "nothing stamps a Call's
result representation" -- and dispatched a diagnosis. The hypothesis is
false, and testing it directly was what showed that: hand-stamping the Call
does not resolve the shape failures, and for F5/F8/F14/F15 it PRODUCES A
MISCOMPILE (`'%tmp_5' defined with type 'double' but expected 'i64'`). The
stamp has to be DERIVED; asserting it is unsound.

THE FRAMING ERROR FIRST. "GAP: Call(new).default.field reached LLVM backend
with NO representation" names no Call node. `Call(new).default.field` is the
$where LABEL passed to _require_repr at Target/LLVM/Context.pm:8056; the
offending node is an ArrayLiteral. I read a diagnostic string as a node kind
and built a cluster on it.

MECHANISM A -- aggregate field default arrives unstamped (2 cases:
classes' arrayref-field element read, foreach over an arrayref field).

For `field $items = [10,20,30]` the wire carries stamp "Unknown" on the
ArrayLiteral and type "ArrayRef" on the CLASS RECORD. The loader drops
Unknown deliberately, so the node loads with representation undef -- the
producer computed the answer and put it somewhere the node-level recovery
does not look.

Analysis.pm:1278 tries to recover it and CANNOT:

    ($default_node->representation // '') =~ /^(?:Array|Hash)Literal$/

That matches a REPRESENTATION field against an OPERATION name. A
representation is never `ArrayLiteral`; the condition is dead. Its comment
says the node is "already repr-seeded ArrayRef/HashRef by %_SEED_REPR" --
but that seed was deliberately removed and %_SEED_REPR is now
`(RegexMatch => 'Boolean')` alone. THE COMMENT OUTLIVED THE TABLE, and the
dead branch is a fossil of it.

Proven: stamping that one node ArrayRef takes `arrayref-field element read`
to SHAPE PASS + lli "10" == perl "10", fully green from a one-node change.

MECHANISM B -- a vacuous widening Coerce freezes arithmetic at Num
(7 cases: F5, F8, F14, F15; classes' field-attrs, field-attrs-custom-param,
method-call, method-call-chain, adjust). All report
`missing [Coerce(Int -> Str) :Str, <op> :Int]`.

The producer cannot type `shift @_`, emits Coerce[Scalar -> Num] and stamps
Add :Num. Chalk's fixpoint DOES narrow the read to Call(shift) :Int -- the
meet fix at Analysis.pm:976 works. But _narrow_unknown_coercions rebuilds
the Coerce copying `to_repr => $c->to_repr` VERBATIM (line 1171), narrowing
only from_repr. The result is Coerce[Int -> Num], a vacuous widening, and
the identity-elision at line 1160 never fires because Int ne Num. Add keeps
its wire Num because _propagate_computed_reprs skips anything _is_narrowed,
and Num counts as narrowed.

Compounding it: _narrow_unknown_coercions runs ONCE, LAST (line 423), after
every repr fixpoint has finished. Nothing re-propagates behind it.

THE CORPUS ir BLOCKS ARE NOT STALE HERE. `f(10)` where f computes `$x + 1`
is Int and perl prints 11. `:Int` is right and the graph is wrong -- the
opposite of the several cases where a stale spec was the defect.

MECHANISM C -- the producer sends type "Scalar" for a scalar field default
(1 case: classes' field-str-default). It infers ArrayRef for an aggregate
default but only Scalar for `"hi"`. Scalar has no machine encoding, so
lowering emits a %Slot where an i64 is wanted. The default graph's Return
stamp has the answer and is already loaded.

SMALLEST CHANGE CLOSING THE MOST (7 of 10), not implemented here:
_narrow_unknown_coercions must narrow to_repr alongside from_repr (guarded
by is_subtype so it never widens), and must run INSIDE the fixpoint rather
than after it. The fiddly part is that nodes whose repr came through a
retargeted Coerce need revisiting, and _is_narrowed will refuse -- so it
needs the "fold the existing stamp into a meet" shape _seed_direct_call_arg
_reprs already uses, not a plain clear-and-rejoin.

EXPLICITLY UNCONFIRMED: whether that terminates. _is_narrowed is the
fixpoint's termination latch, pinned by is-narrowed-guards.t and
propagate-fixpoint-terminates.t, and two comments in the file warn that
loosening it hangs the loop. Those tests are the gate on any attempt.

AND NOT %_SEED_REPR, for any of the three. One ArrayLiteral op builds both
`[1,2,3]` and `my @a = (...)`, so op-keyed seeding conflates them -- which
is why the table was removed. Rebuilding it would restore the exact defect
whose fossil comment is Mechanism A's bug.

Diagnosis only; no lib/ change in this commit.

Claude-Session: https://claude.ai/code/session_018s53vG3TsdscZhiB5ufrdM
