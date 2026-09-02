# ABOUTME: Loop-carried list accumulator step in the Chalk IR (map/grep block lowering).
# ABOUTME: Appends this iteration's contributions to the accumulator in inputs[0].
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Chalk::IR::Value;

class Chalk::IR::Node::ListAppend :isa(Chalk::IR::Value) {

    # inputs[0] is the accumulator being appended to; inputs[1..] are this
    # iteration's contributions. ARITY IS VARIABLE and carries no fixed
    # meaning per slot -- measured against the producer:
    #
    #   grep { $_ > 1 } (3,1,2)   ListAppend(acc, element, predicate)
    #   map  { $_ * 2 } (1,2)     ListAppend(acc, value)
    #   map  { ($_, $_) } (1,2)   ListAppend(acc, value, value)
    #
    # So a 3-input ListAppend is NOT necessarily a guarded append: grep's
    # third input is a Boolean gate, map's is a second contribution. Nothing
    # on the wire distinguishes them -- a consumer that must tell them apart
    # has to read the input's own stamp, not the arity. There are no wire
    # `fields` on this op, so no loader arm is needed for it.
    method operation() { 'ListAppend' }
    method staleness_kind() { 'opaque' }

    # PER-CALL, not hash-consed. Two appends against the same accumulator with
    # the same contribution are two distinct appends -- merging them would drop
    # an element -- so identity must not depend on the inputs hashing apart.
    #
    # Hash-consing happens to be safe against the CURRENT producer, whose
    # inputs[0] is always a loop Phi (per-call by Node.pm's default, keyed by
    # region), so two loops' appends cannot collide. Relying on that would
    # borrow this node's correctness from another class's identity_kind, and
    # it lapses the moment a ListAppend takes a non-Phi first input -- e.g. a
    # nested map feeding another. Standing on its own costs nothing: an append
    # is a distinct step at a distinct loop position, like the Phi it feeds.
    sub identity_kind { 'per_call' }
}
