# ABOUTME: Binary float addition node in the IR graph
# ABOUTME: Represents addition of two float operands (left + right)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::AddF {
    use Chalk::IR::Type::Float;
    use Chalk::IR::Type::Top;
    use Chalk::IR::Node::Constant;

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

    method op() { 'AddF' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'AddF',
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
        return $left_val + $right_val;
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
                type  => $type,
                value => $type->value,
            );
        }

        # Step 2: Algebraic simplification via idealize()
        if (my $idealized = $self->idealize()) {
            return $idealized->peephole();
        }

        return $self;
    }

    # Type inference for constant folding - if both inputs are constant, compute sum
    method compute() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        if ($left_type->is_constant && $right_type->is_constant) {
            return Chalk::IR::Type::Float->constant(
                $left_type->value + $right_type->value
            );
        }

        # If either operand is a float type, result is unknown float
        if (($left_type isa Chalk::IR::Type::Float) ||
            ($right_type isa Chalk::IR::Type::Float)) {
            return Chalk::IR::Type::Float->TOP();
        }

        return Chalk::IR::Type::Top->top();
    }

    # Algebraic simplification for float addition
    method idealize() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        # x + 0.0 -> x (identity right)
        if ($right_type->is_constant && $right_type->value == 0.0) {
            return $left;
        }

        # 0.0 + x -> x (identity left)
        if ($left_type->is_constant && $left_type->value == 0.0) {
            return $right;
        }

        # Canonicalization: swap operands to put constants on right
        # Goal: non-constants on left, constants on right for left-spine structure
        # const + expr -> expr + const
        if ($left_type->is_constant && !$right_type->is_constant) {
            return $self->swap12();
        }

        # Canonicalization: right association to left - flatten right-nested AddFs
        # x + (y + z) -> (x + y) + z
        # This creates a left-spine structure for easier optimization
        # Register dependency on right child since we check its op
        $right->add_dep($self->id);
        if ($right->op eq 'AddF') {
            # right is (y + z), we are x + (y + z)
            # Transform to (x + y) + z
            my $new_left = Chalk::IR::Node::AddF->new(
                left  => $left,
                right => $right->left,
            );
            return Chalk::IR::Node::AddF->new(
                left  => $new_left,
                right => $right->right,
            );
        }

        # Canonicalization for left-spine AddF structures
        # Register dependency on left child since we check its op
        $left->add_dep($self->id);
        if ($left->op eq 'AddF') {
            # Register dependencies on grandchildren since we access them
            $left->left->add_dep($self->id);
            $left->right->add_dep($self->id);

            my $lhs_inner_left_type = $left->left->compute();
            my $lhs_inner_right_type = $left->right->compute();

            # Constant combining: (x + c1) + c2 -> x + (c1 + c2)
            # Only when outer right is also constant
            if ($right_type->is_constant) {
                # Case 1: (x + c1) + c2 -> x + (c1 + c2) - inner already normalized
                if ($lhs_inner_right_type->is_constant) {
                    my $combined_value = $lhs_inner_right_type->value + $right_type->value;
                    my $combined = Chalk::IR::Node::Constant->new(
                        type  => Chalk::IR::Type::Float->constant($combined_value),
                        value => $combined_value,
                    );
                    return Chalk::IR::Node::AddF->new(
                        left  => $left->left,
                        right => $combined,
                    );
                }

                # Case 2: (c1 + x) + c2 -> x + (c1 + c2) - inner not yet normalized
                if ($lhs_inner_left_type->is_constant) {
                    my $combined_value = $lhs_inner_left_type->value + $right_type->value;
                    my $combined = Chalk::IR::Node::Constant->new(
                        type  => Chalk::IR::Type::Float->constant($combined_value),
                        value => $combined_value,
                    );
                    return Chalk::IR::Node::AddF->new(
                        left  => $left->right,
                        right => $combined,
                    );
                }
            }

            # Spline sorting: push constants to the right to group non-constants together
            # (x + c) + z where z is non-constant -> (x + z) + c
            # This enables x + x optimization when x and z are the same
            if ($lhs_inner_right_type->is_constant && !$right_type->is_constant) {
                my $new_left = Chalk::IR::Node::AddF->new(
                    left  => $left->left,
                    right => $right,
                );
                # Peephole the new inner AddF to trigger optimizations
                $new_left = $new_left->peephole();
                return Chalk::IR::Node::AddF->new(
                    left  => $new_left,
                    right => $left->right,
                );
            }

            # Spline sorting: (x + y) + z where both y and z are non-constants
            # Sort by node id for deterministic ordering
            if (!$lhs_inner_right_type->is_constant && !$right_type->is_constant) {
                my $y = $left->right;
                my $z = $right;
                if ($z->id < $y->id) {
                    my $new_left = Chalk::IR::Node::AddF->new(
                        left  => $left->left,
                        right => $z,
                    );
                    return Chalk::IR::Node::AddF->new(
                        left  => $new_left,
                        right => $y,
                    );
                }
            }
        }

        return;
    }

    # Helper method to swap operands (returns new AddF with swapped left/right)
    method swap12() {
        return Chalk::IR::Node::AddF->new(
            left  => $right,
            right => $left,
        );
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }

}

1;
