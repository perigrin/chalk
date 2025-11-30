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
# Subtract::idealize() tests (no optimizations expected)
# =============================================================================

subtest 'Subtract: no optimizations' => sub {
    my $a = const(10);
    my $b = const(3);
    my $sub = Chalk::IR::Node::Subtract->new(left => $a, right => $b);

    my $result = $sub->idealize();
    ok(!$result, 'Subtract::idealize() returns nothing');
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
