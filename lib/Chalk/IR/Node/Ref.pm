# ABOUTME: Reference constructor operation node in the Chalk IR.
# ABOUTME: Unary data node wrapping the \ operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::UnaryOp;

class Chalk::IR::Node::Ref :isa(Chalk::IR::Node::UnaryOp) {
    method operation() { 'Ref' }
    method staleness_kind() { 'transparent' }
    sub identity_kind { 'hash_consed' }
    method op_str()    { '\\' }

    # `\(@a)`: a reference to each element of its operand. Identity-bearing:
    # `\@a` beside it must not hash-cons with it.
    field $each :param :reader = 0;
    # `\$x` of a `my` a loop renews each pass (B::SoN says so): each pass's
    # reference is to that pass's variable.
    field $fresh_each_pass :param :reader = 0;

    method content_hash() {
        return join('|', 'Ref', ($each ? 'each' : ()), ($fresh_each_pass ? 'fresh' : ()), $self->_serialize_inputs());
    }
}
