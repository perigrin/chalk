# ABOUTME: Unary negation node in the IR graph
# ABOUTME: Represents negation of a single operand (-operand)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Negate {
    field $operand :param :reader;
    field $source_info :param :reader = undef;

    field $id :reader = "neg_" . $operand->id;

    # Compute inputs from child node
    method inputs() {
        return [ $operand->id ];
    }

    method op() { 'Negate' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Negate',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand->id,
            },
        };
    }

    method execute($context) {
        my $operand_val = $context->("node:" . $operand->id);
        return -$operand_val;
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
