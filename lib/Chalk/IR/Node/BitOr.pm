# ABOUTME: Bitwise OR operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the | operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::BinOp;

class Chalk::IR::Node::BitOr :isa(Chalk::IR::Node::BinOp) {
    method operation() { 'BitOr' }
    method staleness_kind() { 'transparent' }
    sub identity_kind { 'hash_consed' }
    method op_str()    { '|' }

    # numeric or string (`&.`), as the producer read the op; none: perl decides
    # from its operands at run time. Identity-bearing.
    field $flavor :param :reader = undef;

    method content_hash() {
        return join('|', $self->operation, ( $flavor // () ), $self->_serialize_inputs());
    }
}
