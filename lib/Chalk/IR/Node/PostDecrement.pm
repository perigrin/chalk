# ABOUTME: Post-decrement node in the IR graph
# ABOUTME: Represents post-decrement operation ($var--) - returns current value then decrements
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::PostDecrement {
    field $operand :param :reader;
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    method id() { refaddr($self) }

    method inputs() {
        return [ $operand->id ];
    }

    method op() { 'PostDecrement' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'PostDecrement',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand->id,
            },
        };
    }

    method execute($context) {
        my $val = $context->("node:" . $operand->id);
        return $val;  # Post-decrement: return original value (decrement happens as side effect)
    }

    # Compatibility methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph) {
        return $self;
    }

    method record_transform(@args) {
        return;
    }

}

1;
