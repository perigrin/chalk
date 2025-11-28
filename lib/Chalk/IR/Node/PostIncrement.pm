# ABOUTME: Post-increment node in the IR graph
# ABOUTME: Represents post-increment operation ($var++) - returns current value then increments
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::PostIncrement {
    field $operand :param :reader;
    field $source_info :param :reader = undef;

    field $id :reader = "postincr_" . $operand->id;

    method inputs() {
        return [ $operand->id ];
    }

    method op() { 'PostIncrement' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'PostIncrement',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand->id,
            },
        };
    }

    method execute($context) {
        my $val = $context->("node:" . $operand->id);
        return $val;  # Post-increment: return original value (increment happens as side effect)
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
