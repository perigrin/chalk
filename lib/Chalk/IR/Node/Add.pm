# ABOUTME: Binary addition node in the IR graph
# ABOUTME: Represents addition of two operands (left + right)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Add {

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

    method op() { 'Add' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Add',
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

    # Type inference for constant folding - if both inputs are constant, compute sum
    method compute() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        if ($left_type->is_constant && $right_type->is_constant) {
            return Chalk::IR::Type::Integer->constant(
                $left_type->value + $right_type->value
            );
        }

        # If either operand is an integer type, result is unknown integer
        if (($left_type isa Chalk::IR::Type::Integer) ||
            ($right_type isa Chalk::IR::Type::Integer)) {
            return Chalk::IR::Type::Integer->TOP();
        }

        return Chalk::IR::Type::Top->top();
    }

    # Algebraic simplification for addition
    method idealize() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        # x + 0 -> x (identity right)
        if ($right_type->is_constant && $right_type->value == 0) {
            return $left;
        }

        # 0 + x -> x (identity left)
        if ($left_type->is_constant && $left_type->value == 0) {
            return $right;
        }

        # x + x -> x * 2 (doubling)
        if ($left->id eq $right->id) {
            return Chalk::IR::Node::Multiply->new(
                left  => $left,
                right => Chalk::IR::Node::Constant->new(value => 2, type => 'Integer'),
            );
        }

        # Canonicalization: swap operands to put constants on right
        # Goal: non-constants on left, constants on right for left-spine structure
        # const + expr -> expr + const
        if ($left_type->is_constant && !$right_type->is_constant) {
            return $self->swap12();
        }

        # Canonicalization: right association to left - flatten right-nested Adds
        # x + (y + z) -> (x + y) + z
        # This creates a left-spine structure for easier optimization
        # Register dependency on right child since we check its op (Issue #282)
        $right->add_dep($self->id);
        if ($right->op eq 'Add') {
            # right is (y + z), we are x + (y + z)
            # Transform to (x + y) + z
            my $new_left = Chalk::IR::Node::Add->new(
                left  => $left,
                right => $right->left,
            );
            return Chalk::IR::Node::Add->new(
                left  => $new_left,
                right => $right->right,
            );
        }

        # Canonicalization for left-spine Add structures
        # Register dependency on left child since we check its op (Issue #282)
        $left->add_dep($self->id);
        if ($left->op eq 'Add') {
            # Register dependencies on grandchildren since we access them (Issue #282)
            $left->left->add_dep($self->id);
            $left->right->add_dep($self->id);

            my $lhs_inner_left_type = $left->left->compute();
            my $lhs_inner_right_type = $left->right->compute();

            # Constant combining: (x + c1) + c2 -> x + (c1 + c2)
            # Only when outer right is also constant
            if ($right_type->is_constant) {
                # Case 1: (x + c1) + c2 -> x + (c1 + c2) - inner already normalized
                if ($lhs_inner_right_type->is_constant) {
                    my $combined = Chalk::IR::Node::Constant->new(
                        value => $lhs_inner_right_type->value + $right_type->value,
                        type  => 'Integer',
                    );
                    return Chalk::IR::Node::Add->new(
                        left  => $left->left,
                        right => $combined,
                    );
                }

                # Case 2: (c1 + x) + c2 -> x + (c1 + c2) - inner not yet normalized
                if ($lhs_inner_left_type->is_constant) {
                    my $combined = Chalk::IR::Node::Constant->new(
                        value => $lhs_inner_left_type->value + $right_type->value,
                        type  => 'Integer',
                    );
                    return Chalk::IR::Node::Add->new(
                        left  => $left->right,
                        right => $combined,
                    );
                }
            }

            # Spline sorting: push constants to the right to group non-constants together
            # (x + c) + z where z is non-constant -> (x + z) + c
            # This enables x + x -> x * 2 optimization when x and z are the same
            if ($lhs_inner_right_type->is_constant && !$right_type->is_constant) {
                my $new_left = Chalk::IR::Node::Add->new(
                    left  => $left->left,
                    right => $right,
                );
                # Peephole the new inner Add to trigger optimizations like x+x->x*2
                $new_left = $new_left->peephole();
                return Chalk::IR::Node::Add->new(
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
                    my $new_left = Chalk::IR::Node::Add->new(
                        left  => $left->left,
                        right => $z,
                    );
                    return Chalk::IR::Node::Add->new(
                        left  => $new_left,
                        right => $y,
                    );
                }
            }
        }

        return;
    }

    # Helper method to swap operands (returns new Add with swapped left/right)
    method swap12() {
        return Chalk::IR::Node::Add->new(
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
