# ABOUTME: Pre-decrement node in the IR graph
# ABOUTME: Represents pre-decrement operation (--$var) - decrements then returns new value
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::PreDecrement {
    field $operand :param :reader;
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    method id() { refaddr($self) }

    method inputs() {
        return [ $operand->id ];
    }

    method op() { 'PreDecrement' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'PreDecrement',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand->id,
            },
        };
    }

    method execute($context) {
        my $val = $context->("node:" . $operand->id);
        return $val - 1;  # Pre-decrement: return decremented value
    }

    # Compatibility methods for code expecting Base methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        return $self;
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }

}

1;
