# ABOUTME: Binary subtraction node in the IR graph
# ABOUTME: Represents subtraction of two operands (left - right)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Subtract {
    field $left :param :reader;
    field $right :param :reader;
    field $source_info :param :reader = undef;

    field $id;

    ADJUST {
        die "Subtract: left operand is required and must have id() method"
            unless blessed($left) && $left->can('id');
        die "Subtract: right operand is required and must have id() method"
            unless blessed($right) && $right->can('id');
    }

    # Content-addressable ID computed from operand IDs
    method id() {
        return $id if defined $id;
        return $id = "sub_" . $left->id . "_" . $right->id;
    }

    # Compute inputs from child nodes
    method inputs() {
        return [ $left->id, $right->id ];
    }

    method op() { 'Subtract' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Subtract',
            inputs => $self->inputs,
            attributes => {
                left_id  => $left->id,
                right_id => $right->id,
            },
        };
    }

    method execute($context) {
        my $left_val = $context->("node:" . $left->id);
        my $right_val = $context->("node:" . $right->id);
        return $left_val - $right_val;
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

    method get_transform_chain() {
        return [];
    }
}

1;
