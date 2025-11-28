# ABOUTME: Binary division node in the IR graph
# ABOUTME: Represents division of two operands (left / right)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Divide {
    field $left :param :reader;
    field $right :param :reader;
    field $source_info :param :reader = undef;

    field $id;

    ADJUST {
        die "Divide: left operand is required and must have id() method"
            unless blessed($left) && $left->can('id');
        die "Divide: right operand is required and must have id() method"
            unless blessed($right) && $right->can('id');
    }

    # Content-addressable ID computed from operand IDs
    method id() {
        return $id if defined $id;
        return $id = "div_" . $left->id . "_" . $right->id;
    }

    # Compute inputs from child nodes
    method inputs() {
        return [ $left->id, $right->id ];
    }

    method op() { 'Divide' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Divide',
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
        return $left_val / $right_val;
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
