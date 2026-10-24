# ABOUTME: Assignment operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the = operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::BinOp;

class Chalk::IR::Node::Assign :isa(Chalk::IR::Node::BinOp) {
    method operation() { 'Assign' }
    method staleness_kind() { 'opaque' }

    # FIXED: a store: it writes, so it is pinned to a point in the chain
    method is_fixed() { return true }
    method op_str()    { '=' }

    # A LIST assignment's target count: inputs[0 .. targets-1] are the
    # targets, the rest the values. Undef for a scalar assign. In the content
    # hash, since Assign(a, b, c) means a different store for 1 than for 2.
    field $targets :param :reader = undef;
    method content_hash() {
        return join('|', 'Assign', (defined $targets ? "targets=$targets" : ()),
            $self->_serialize_inputs());
    }
}
