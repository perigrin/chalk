# ABOUTME: IR node for array or hash subscript operations in the Sea of Nodes graph.
# ABOUTME: inputs->[0] is the container, inputs->[1] is the index or key.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Access;

class Chalk::IR::Node::Subscript :isa(Chalk::IR::Node::Access) {
    method operation() { 'Subscript' }

    # memory_operand -> it reads at its third input (after the aggregate and the key).
    method memory_operand() { return $self->inputs->[2] }

    # A MEMORY VERSION where pinned: B::SoN pins a read of a tied aggregate (a
    # method call) and versions memory at it.
    method is_memory_version() { return $self->is_pinned }
    sub identity_kind { q(hash_consed) }

    # 'array' or 'hash' (B::SoN's kind): which aggregate the read indexes,
    # said even where the container's own type does not (a value read by
    # its tag that holds the reference).
    field $kind :reader = undef;

    method set_kind($k) {
        $kind = $k;
        return;
    }
}
