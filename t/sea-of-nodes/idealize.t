# ABOUTME: Tests for idealize() algebraic simplification methods
# ABOUTME: Validates identity, zero, and doubling optimizations for arithmetic nodes

use lib 'lib';
use v5.42;
use Test::More;

use_ok('Chalk::IR::Node::Add');
use_ok('Chalk::IR::Node::Multiply');
use_ok('Chalk::IR::Node::Divide');
use_ok('Chalk::IR::Node::Subtract');
use_ok('Chalk::IR::Node::Negate');
use_ok('Chalk::IR::Node::Constant');
use_ok('Chalk::IR::Node::EQ');
use_ok('Chalk::IR::Node::NE');

# Helper to create constant nodes
sub const {
    my ($val) = @_;
    return Chalk::IR::Node::Constant->new(value => $val, type => 'Integer');
}

# =============================================================================
# Add::idealize() tests
# =============================================================================

subtest 'Add: x + 0 -> x (identity right)' => sub {
    my $x = const(42);
    my $zero = const(0);
    my $add = Chalk::IR::Node::Add->new(left => $x, right => $zero);

    my $result = $add->idealize();
    ok($result, 'idealize() returns a replacement');
    is($result->id, $x->id, 'x + 0 returns x');
};

subtest 'Add: 0 + x -> x (identity left)' => sub {
    my $x = const(42);
    my $zero = const(0);
    my $add = Chalk::IR::Node::Add->new(left => $zero, right => $x);

    my $result = $add->idealize();
    ok($result, 'idealize() returns a replacement');
    is($result->id, $x->id, '0 + x returns x');
};

subtest 'Add: x + x -> x * 2 (doubling)' => sub {
    my $x = const(21);
    my $add = Chalk::IR::Node::Add->new(left => $x, right => $x);

    my $result = $add->idealize();
    ok($result, 'idealize() returns a replacement');
    is($result->op, 'Multiply', 'x + x becomes Multiply');
    is($result->left->id, $x->id, 'left operand is x');
    is($result->right->op, 'Constant', 'right operand is Constant');
    is($result->right->value, 2, 'right operand is 2');
};

subtest 'Add: no optimization for non-zero constants' => sub {
    my $a = const(5);
    my $b = const(3);
    my $add = Chalk::IR::Node::Add->new(left => $a, right => $b);

    my $result = $add->idealize();
    ok(!$result, 'idealize() returns nothing when no optimization applies');
};

# =============================================================================
# Multiply::idealize() tests
# =============================================================================

subtest 'Multiply: x * 1 -> x (identity right)' => sub {
    my $x = const(42);
    my $one = const(1);
    my $mul = Chalk::IR::Node::Multiply->new(left => $x, right => $one);

    my $result = $mul->idealize();
    ok($result, 'idealize() returns a replacement');
    is($result->id, $x->id, 'x * 1 returns x');
};

subtest 'Multiply: 1 * x -> x (identity left)' => sub {
    my $x = const(42);
    my $one = const(1);
    my $mul = Chalk::IR::Node::Multiply->new(left => $one, right => $x);

    my $result = $mul->idealize();
    ok($result, 'idealize() returns a replacement');
    is($result->id, $x->id, '1 * x returns x');
};

subtest 'Multiply: x * 0 -> 0 (zero right)' => sub {
    my $x = const(42);
    my $zero = const(0);
    my $mul = Chalk::IR::Node::Multiply->new(left => $x, right => $zero);

    my $result = $mul->idealize();
    ok($result, 'idealize() returns a replacement');
    is($result->op, 'Constant', 'x * 0 returns Constant');
    is($result->value, 0, 'result is 0');
};

subtest 'Multiply: 0 * x -> 0 (zero left)' => sub {
    my $x = const(42);
    my $zero = const(0);
    my $mul = Chalk::IR::Node::Multiply->new(left => $zero, right => $x);

    my $result = $mul->idealize();
    ok($result, 'idealize() returns a replacement');
    is($result->op, 'Constant', '0 * x returns Constant');
    is($result->value, 0, 'result is 0');
};

subtest 'Multiply: no optimization for non-identity constants' => sub {
    my $a = const(5);
    my $b = const(3);
    my $mul = Chalk::IR::Node::Multiply->new(left => $a, right => $b);

    my $result = $mul->idealize();
    ok(!$result, 'idealize() returns nothing when no optimization applies');
};

# =============================================================================
# Divide::idealize() tests
# =============================================================================

subtest 'Divide: x / 1 -> x (identity)' => sub {
    my $x = const(42);
    my $one = const(1);
    my $div = Chalk::IR::Node::Divide->new(left => $x, right => $one);

    my $result = $div->idealize();
    ok($result, 'idealize() returns a replacement');
    is($result->id, $x->id, 'x / 1 returns x');
};

subtest 'Divide: no optimization for non-identity divisor' => sub {
    my $a = const(10);
    my $b = const(2);
    my $div = Chalk::IR::Node::Divide->new(left => $a, right => $b);

    my $result = $div->idealize();
    ok(!$result, 'idealize() returns nothing when no optimization applies');
};

# =============================================================================
# Subtract::idealize() tests
# =============================================================================

subtest 'Subtract: x - x -> 0 (self-subtraction elimination)' => sub {
    my $x = const(42);
    my $sub = Chalk::IR::Node::Subtract->new(left => $x, right => $x);

    my $result = $sub->idealize();
    ok($result, 'idealize() returns a replacement');
    is($result->op, 'Constant', 'x - x returns Constant');
    is($result->value, 0, 'x - x returns 0');
};

subtest 'Subtract: no optimization for different operands' => sub {
    my $a = const(10);
    my $b = const(3);
    my $sub = Chalk::IR::Node::Subtract->new(left => $a, right => $b);

    my $result = $sub->idealize();
    ok(!$result, 'Subtract::idealize() returns nothing for different operands');
};

# =============================================================================
# Negate::idealize() tests (no optimizations expected)
# =============================================================================

subtest 'Negate: no optimizations' => sub {
    my $x = const(42);
    my $neg = Chalk::IR::Node::Negate->new(operand => $x);

    my $result = $neg->idealize();
    ok(!$result, 'Negate::idealize() returns nothing');
};

# =============================================================================
# EQ::idealize() tests
# =============================================================================

subtest 'EQ: x == x -> true (self-equality)' => sub {
    my $x = const(42);
    my $eq = Chalk::IR::Node::EQ->new(left => $x, right => $x);

    my $result = $eq->idealize();
    ok($result, 'idealize() returns a replacement');
    is($result->op, 'Constant', 'x == x returns Constant');
    is($result->value, true, 'x == x returns true');
};

subtest 'EQ: no optimization for different operands' => sub {
    my $a = const(5);
    my $b = const(3);
    my $eq = Chalk::IR::Node::EQ->new(left => $a, right => $b);

    my $result = $eq->idealize();
    ok(!$result, 'EQ::idealize() returns nothing for different operands');
};

# =============================================================================
# NE::idealize() tests
# =============================================================================

subtest 'NE: x != x -> false (self-inequality)' => sub {
    my $x = const(42);
    my $ne = Chalk::IR::Node::NE->new(left => $x, right => $x);

    my $result = $ne->idealize();
    ok($result, 'idealize() returns a replacement');
    is($result->op, 'Constant', 'x != x returns Constant');
    is($result->value, false, 'x != x returns false');
};

subtest 'NE: no optimization for different operands' => sub {
    my $a = const(5);
    my $b = const(3);
    my $ne = Chalk::IR::Node::NE->new(left => $a, right => $b);

    my $result = $ne->idealize();
    ok(!$result, 'NE::idealize() returns nothing for different operands');
};

# =============================================================================
# Expression Canonicalization Tests (Issue #225)
# Chapter 4: Transform expressions like 1 + arg + 2 into arg + 3
# =============================================================================

use_ok('Chalk::IR::Node::Start');
use_ok('Chalk::IR::Node::Proj');

# Helper to create an "arg" variable node (unknown integer value at compile time)
sub make_arg {
    my $start = Chalk::IR::Node::Start->new(label => 'main');
    return Chalk::IR::Node::Proj->new(
        source => $start,
        index => 1,
        label => 'arg',
        inputs => [$start->id],
    );
}

subtest 'Canonicalization: swap operands - move non-Add to right side' => sub {
    # When left is constant and right is not, swap to normalize
    # const + arg -> arg + const
    my $arg = make_arg();
    my $c1 = const(5);
    my $add = Chalk::IR::Node::Add->new(left => $c1, right => $arg);

    my $result = $add->idealize();
    if (ok($result, 'idealize() returns a replacement for constant on left')) {
        is($result->op, 'Add', 'Result is still Add');
        is($result->left->id, $arg->id, 'arg moved to left (non-constant on LHS)');
        is($result->right->id, $c1->id, 'constant moved to right');
    }
};

subtest 'Canonicalization: no swap when already normalized' => sub {
    # arg + const is already normalized
    my $arg = make_arg();
    my $c1 = const(5);
    my $add = Chalk::IR::Node::Add->new(left => $arg, right => $c1);

    my $result = $add->idealize();
    ok(!$result, 'idealize() returns nothing when already normalized');
};

subtest 'Canonicalization: right association to left - x + (y + z) -> (x + y) + z' => sub {
    # This ensures we have a left-spine structure for easier optimization
    my $x = make_arg();
    my $c1 = const(1);
    my $c2 = const(2);

    # x + (1 + 2) - though constants will fold, test the structure
    my $inner = Chalk::IR::Node::Add->new(left => $c1, right => $c2);
    my $outer = Chalk::IR::Node::Add->new(left => $x, right => $inner);

    my $result = $outer->idealize();
    # The inner Add is constant-foldable, so peephole should handle it
    # But idealize should rotate: x + (y + z) -> (x + y) + z
    if (ok($result, 'idealize() returns a rotation')) {
        is($result->op, 'Add', 'Result is Add');
        # After rotation: (x + 1) + 2
        is($result->left->op, 'Add', 'Left is now Add node (rotated)');
    }
};

subtest 'Canonicalization: constant combining - (x + c1) + c2 -> x + (c1 + c2)' => sub {
    # 1 + arg + 2 should become arg + 3
    my $arg = make_arg();
    my $c1 = const(1);
    my $c2 = const(2);

    # Build: (1 + arg) + 2
    my $inner = Chalk::IR::Node::Add->new(left => $c1, right => $arg);
    my $outer = Chalk::IR::Node::Add->new(left => $inner, right => $c2);

    # After peephole optimization chain:
    # Step 1: inner idealizes to (arg + 1) - swap constants to right
    # Step 2: outer becomes (arg + 1) + 2
    # Step 3: constant combining: arg + (1 + 2) = arg + 3
    my $result = $outer->peephole();
    if (ok($result, 'peephole returns a result')) {
        if (is($result->op, 'Add', 'Result is Add')) {
            is($result->left->id, $arg->id, 'Left is arg');
            if (ok($result->right, 'Right operand exists')) {
                is($result->right->op, 'Constant', 'Right is Constant');
                is($result->right->value, 3, 'Constants combined: 1 + 2 = 3');
            }
        }
    }
};

subtest 'Canonicalization: arg + 1 + arg -> (arg + arg) + 1 -> (arg * 2) + 1' => sub {
    my $arg = make_arg();
    my $c1 = const(1);

    # Build: (arg + 1) + arg
    my $inner = Chalk::IR::Node::Add->new(left => $arg, right => $c1);
    my $outer = Chalk::IR::Node::Add->new(left => $inner, right => $arg);

    # After canonicalization and optimization:
    # Should become (arg * 2) + 1
    my $result = $outer->peephole();
    if (ok($result, 'peephole returns a result')) {
        if (is($result->op, 'Add', 'Result is Add')) {
            if (ok($result->left, 'Left operand exists')) {
                if (is($result->left->op, 'Multiply', 'Left is Multiply (arg * 2)')) {
                    is($result->left->left->id, $arg->id, 'Multiply left is arg');
                    is($result->left->right->value, 2, 'Multiply right is 2');
                }
            }
            if (ok($result->right, 'Right operand exists')) {
                is($result->right->op, 'Constant', 'Right is Constant');
                is($result->right->value, 1, 'Right value is 1');
            }
        }
    }
};

# =============================================================================
# Peephole recursion termination tests
# =============================================================================

subtest 'Peephole recursion terminates: 0 + 0 folds to 0' => sub {
    my $zero = const(0);
    my $add = Chalk::IR::Node::Add->new(left => $zero, right => $zero);

    # This triggers: idealize returns $left (which is 0), then peephole on Constant
    my $result = $add->peephole();
    is($result->op, 'Constant', 'Deeply folded to Constant');
    is($result->value, 0, 'Value is 0');
};

subtest 'Peephole recursion terminates: x + x -> x * 2 -> constant' => sub {
    my $five = const(5);
    my $add = Chalk::IR::Node::Add->new(left => $five, right => $five);

    # This triggers: idealize returns Multiply(5, 2), then peephole folds to 10
    my $result = $add->peephole();
    is($result->op, 'Constant', 'x + x folded through Multiply to Constant');
    is($result->value, 10, 'Value is 10 (5 * 2)');
};

subtest 'Peephole recursion terminates: chained identity' => sub {
    my $x = const(42);
    my $zero = const(0);
    my $one = const(1);

    # (x + 0) * 1 should fold to x
    my $add = Chalk::IR::Node::Add->new(left => $x, right => $zero);
    my $mul = Chalk::IR::Node::Multiply->new(left => $add, right => $one);

    my $result = $mul->peephole();
    is($result->op, 'Constant', 'Chained identities fold to Constant');
    is($result->value, 42, 'Value is 42');
};

done_testing();
