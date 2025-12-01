# ABOUTME: Binary division node in the IR graph
# ABOUTME: Represents division of two operands (left / right)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Divide {
    use Chalk::IR::Type::TypeInteger;
    use Chalk::IR::Type::Top;
    use Chalk::IR::Node::Constant;

    field $left :param :reader;
    field $right :param :reader;
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    ADJUST {
        die "left operand is required" unless defined $left;
        die "right operand is required" unless defined $right;
        die "left operand must have id()" unless blessed($left) && $left->can('id');
        die "right operand must have id()" unless blessed($right) && $right->can('id');
    }

    method id() { refaddr($self) }

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

    method peephole($graph = undef) {
        # Step 1: Constant folding via compute()
        my $type = $self->compute();
        if ($type->is_constant) {
            return Chalk::IR::Node::Constant->new(
                value => $type->value,
                type  => 'Integer',
            );
        }

        # Step 2: Algebraic simplification via idealize()
        if (my $idealized = $self->idealize()) {
            return $idealized->peephole();
        }

        return $self;
    }

    # Type inference for constant folding - if both inputs are constant, compute quotient
    method compute() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        if ($left_type->is_constant && $right_type->is_constant) {
            my $divisor = $right_type->value;
            # Division by zero yields IntBot (error state)
            return Chalk::IR::Type::TypeInteger->BOTTOM() if $divisor == 0;
            return Chalk::IR::Type::TypeInteger->constant(
                int($left_type->value / $divisor)
            );
        }

        # If either operand is an integer type, result is unknown integer
        if (($left_type isa Chalk::IR::Type::TypeInteger) ||
            ($right_type isa Chalk::IR::Type::TypeInteger)) {
            return Chalk::IR::Type::TypeInteger->TOP();
        }

        return Chalk::IR::Type::Top->top();
    }

    # Algebraic simplification for division
    method idealize() {
        my $right_type = $right->compute();

        # x / 1 -> x (identity)
        if ($right_type->is_constant && $right_type->value == 1) {
            return $left;
        }

        return;
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }

}

1;
