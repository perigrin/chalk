# ABOUTME: Binary multiplication node in the IR graph
# ABOUTME: Represents multiplication of two operands (left * right)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Multiply {

    field $left :param :reader;
    field $right :param :reader;
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    # Dependency tracking for peephole re-optimization
    field $_deps = [];

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;
    }

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

    method op() { 'Multiply' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Multiply',
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
        return $left_val * $right_val;
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
                type  => $type,
            );
        }

        # Step 2: Algebraic simplification via idealize()
        if (my $idealized = $self->idealize()) {
            return $idealized->peephole();
        }

        return $self;
    }

    # Type inference for constant folding - if both inputs are constant, compute product
    method compute() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        if ($left_type->is_constant && $right_type->is_constant) {
            return Chalk::IR::Type::Integer->constant(
                $left_type->value * $right_type->value
            );
        }

        # If either operand is an integer type, result is unknown integer
        if (($left_type isa Chalk::IR::Type::Integer) ||
            ($right_type isa Chalk::IR::Type::Integer)) {
            return Chalk::IR::Type::Integer->TOP();
        }

        return Chalk::IR::Type::Top->top();
    }

    # Algebraic simplification for multiplication
    method idealize() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        # x * 1 -> x (identity right)
        if ($right_type->is_constant && $right_type->value == 1) {
            return $left;
        }

        # 1 * x -> x (identity left)
        if ($left_type->is_constant && $left_type->value == 1) {
            return $right;
        }

        # x * 0 -> 0 (zero right, only if x is also constant to preserve side effects)
        if ($right_type->is_constant && $right_type->value == 0) {
            # Only fold if left operand is also constant (no side effects)
            if ($left_type->is_constant) {
                return Chalk::IR::Node::Constant->new(value => 0, type => Chalk::IR::Type::Integer->constant(0));
            }
        }

        # 0 * x -> 0 (zero left, only if x is also constant to preserve side effects)
        if ($left_type->is_constant && $left_type->value == 0) {
            # Only fold if right operand is also constant (no side effects)
            if ($right_type->is_constant) {
                return Chalk::IR::Node::Constant->new(value => 0, type => Chalk::IR::Type::Integer->constant(0));
            }
        }

        return;
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }

}

1;
