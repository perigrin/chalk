# ABOUTME: Logical negation node in the IR graph
# ABOUTME: Represents boolean negation of a single operand (!operand or not operand)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Not {
    field $operand :param :reader;
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    method id() { refaddr($self) }

    # Compute inputs from child node
    method inputs() {
        return [ $operand->id ];
    }

    method op() { 'Not' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Not',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand->id,
            },
        };
    }

    method execute($context) {
        my $operand_val = $context->("node:" . $operand->id);
        return $operand_val ? 0 : 1;
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
