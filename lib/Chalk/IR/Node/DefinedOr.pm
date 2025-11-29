# ABOUTME: Binary defined-or node in the IR graph
# ABOUTME: Represents defined-or of two operands (left // right)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::DefinedOr {
    field $left :param :reader;
    field $right :param :reader;
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    field $id :reader = "definedor_" . $left->id . "_" . $right->id;

    # Compute inputs from child nodes
    method inputs() {
        return [ $left->id, $right->id ];
    }

    method op() { 'DefinedOr' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'DefinedOr',
            inputs => $self->inputs,
            attributes => {
                left_id  => $left->id,
                right_id => $right->id,
            },
        };
    }

    method execute($context) {
        my $left_val = $context->("node:" . $left->id);
        # Short-circuit: only evaluate right if left is undefined
        return $left_val if defined $left_val;
        my $right_val = $context->("node:" . $right->id);
        return $right_val;
    }

    # Compatibility methods for code expecting Base methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph) {
        return $self;
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }

}

1;
