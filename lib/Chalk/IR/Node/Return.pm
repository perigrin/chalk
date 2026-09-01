# ABOUTME: CFG normal-exit node for a Chalk computation graph.
# ABOUTME: inputs[0] is the return value; the control predecessor lives in control_in.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::Return :isa(Chalk::IR::Node) {
    # Marks a Return synthesized by _finalize_body_graph for the
    # implicit fall-through case (the source had a bare trailing
    # expression). Codegen emits a synthetic Return as a bare value;
    # an explicit-source Return emits `return EXPR;`.
    field $synthetic :param :reader = false;

    method operation() { 'Return' }
    method staleness_kind() { 'opaque' }
    sub identity_kind { 'hash_consed' }

    # The returned value in LIST context: all N values. Control flows through
    # the control_in decoration (set via set_control_in), not through an
    # inputs slot.
    #
    # inputs[0], never inputs[-1]. Those coincide only while a Return has ONE
    # input, which every shape did until a list-returning sub gained a second
    # reading -- so no test could distinguish a consumer reading the right slot
    # from one reading the last slot. Three sites in this repo read [-1] and
    # would have silently taken the scalar face.
    method value() { return $self->inputs->[0] }

    # The returned value in SCALAR context, or undef when the return has only
    # one reading. A sub is compiled once and cannot see its caller's context
    # (perl leaves entersub's context slot empty for a call in last-operand
    # position, which is why `wantarray` is a runtime function), so the callee
    # states BOTH readings and the callsite picks by its own `want`.
    #
    # Undef is the honest answer for a bare aggregate return: the container
    # already answers both readings (`return @a` in scalar context is its
    # length), so there is no second value to carry.
    method scalar_value() { return $self->inputs->[1] }
}
