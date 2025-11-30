# ABOUTME: Binary subtraction node in the IR graph
# ABOUTME: Represents subtraction of two operands (left - right)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Subtract {
    use Chalk::IR::Type::TypeInteger;
    use Chalk::IR::Type::Top;
    use Chalk::IR::Node::Constant;

    field $left :param :reader;
    field $right :param :reader;
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    method id() { refaddr($self) }

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
        # Use compute() for constant folding - if both inputs are constant,
        # replace this Subtract with a Constant node containing the difference
        my $type = $self->compute();
        if ($type->is_constant) {
            return Chalk::IR::Node::Constant->new(
                value => $type->value,
                type  => 'Integer',
            );
        }
        return $self;
    }

    # Type inference for constant folding - if both inputs are constant, compute difference
    method compute() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        if ($left_type->is_constant && $right_type->is_constant) {
            return Chalk::IR::Type::TypeInteger->constant(
                $left_type->value - $right_type->value
            );
        }

        return Chalk::IR::Type::Top->top();
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }

}

1;
