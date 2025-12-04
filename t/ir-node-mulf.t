#!/usr/bin/env perl
# ABOUTME: Tests for MulF IR node (floating-point multiplication)
# ABOUTME: Verifies float multiplication node behavior, peephole optimizations, and type computation

use 5.42.0;
use utf8;
use Test::More;
use experimental qw(class);

# Load required modules
use Chalk::IR::Node::MulF;
use Chalk::IR::Node::ConstantF;
use Chalk::IR::Type::Float;

# ============================================================
# MulF node creation and basic properties
# ============================================================

subtest 'MulF node creation' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 3.0);
    my $mul = Chalk::IR::Node::MulF->new(left => $left, right => $right);

    ok($mul, 'MulF node created');
    is($mul->op, 'MulF', 'op is MulF');
    ok($mul->id, 'node has ID');
    is($mul->left->id, $left->id, 'left accessor works');
    is($mul->right->id, $right->id, 'right accessor works');
};

subtest 'MulF node requires operands' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 1.0);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.0);

    eval { Chalk::IR::Node::MulF->new(left => $left) };
    like($@, qr/right.*is (required|missing)/i, 'dies without right operand');

    eval { Chalk::IR::Node::MulF->new(right => $right) };
    like($@, qr/left.*is (required|missing)/i, 'dies without left operand');
};

# ============================================================
# Node properties
# ============================================================

subtest 'MulF inputs()' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 1.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $mul = Chalk::IR::Node::MulF->new(left => $left, right => $right);

    my $inputs = $mul->inputs();
    is(ref($inputs), 'ARRAY', 'inputs returns array ref');
    is(scalar(@$inputs), 2, 'MulF has two inputs');
    is($inputs->[0], $left->id, 'first input is left operand ID');
    is($inputs->[1], $right->id, 'second input is right operand ID');
};

# ============================================================
# Type computation
# ============================================================

subtest 'MulF compute() returns TypeFloat' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 3.0);
    my $mul = Chalk::IR::Node::MulF->new(left => $left, right => $right);

    my $type = $mul->compute();
    isa_ok($type, 'Chalk::IR::Type::Float', 'compute() returns TypeFloat');
    ok($type->is_constant(), 'type is constant when both operands are constant');
    is($type->value, 7.5, 'constant folding: 2.5 * 3.0 = 7.5');
};

subtest 'MulF compute() constant folding' => sub {
    my $mul1 = Chalk::IR::Node::MulF->new(
        left => Chalk::IR::Node::ConstantF->new(value => 2.5),
        right => Chalk::IR::Node::ConstantF->new(value => 3.0)
    );
    is($mul1->compute()->value, 7.5, '2.5 * 3.0 = 7.5');

    my $mul2 = Chalk::IR::Node::MulF->new(
        left => Chalk::IR::Node::ConstantF->new(value => -2.0),
        right => Chalk::IR::Node::ConstantF->new(value => 1.5)
    );
    is($mul2->compute()->value, -3.0, '-2.0 * 1.5 = -3.0');

    my $mul3 = Chalk::IR::Node::MulF->new(
        left => Chalk::IR::Node::ConstantF->new(value => 0.0),
        right => Chalk::IR::Node::ConstantF->new(value => 5.5)
    );
    is($mul3->compute()->value, 0.0, '0.0 * 5.5 = 0.0');
};

# ============================================================
# Execution
# ============================================================

subtest 'MulF execute()' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 3.0);
    my $mul = Chalk::IR::Node::MulF->new(left => $left, right => $right);

    # Create a simple context that returns node values
    my $context = sub {
        my $key = shift;
        if ($key eq "node:" . $left->id) { return 2.5; }
        if ($key eq "node:" . $right->id) { return 3.0; }
        die "Unknown node: $key";
    };

    is($mul->execute($context), 7.5, 'execute() returns 2.5 * 3.0 = 7.5');
};

# ============================================================
# Serialization
# ============================================================

subtest 'MulF to_hash()' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 1.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $mul = Chalk::IR::Node::MulF->new(left => $left, right => $right);

    my $hash = $mul->to_hash();
    is($hash->{op}, 'MulF', 'op is MulF');
    is($hash->{id}, $mul->id, 'id matches');
    is(ref($hash->{inputs}), 'ARRAY', 'inputs is array');
    is(scalar(@{$hash->{inputs}}), 2, 'two inputs');
    is($hash->{attributes}{left_id}, $left->id, 'left_id in attributes');
    is($hash->{attributes}{right_id}, $right->id, 'right_id in attributes');
};

# ============================================================
# Peephole optimizations
# ============================================================

subtest 'MulF peephole constant folding' => sub {
    my $mul = Chalk::IR::Node::MulF->new(
        left => Chalk::IR::Node::ConstantF->new(value => 2.5),
        right => Chalk::IR::Node::ConstantF->new(value => 3.0)
    );

    my $result = $mul->peephole();
    isa_ok($result, 'Chalk::IR::Node::ConstantF', 'constant folding produces ConstantF');
    is($result->value, 7.5, 'folded to constant 7.5');
};

subtest 'MulF idealize identity: x * 1.0 = x' => sub {
    my $x = Chalk::IR::Node::ConstantF->new(value => 5.5);
    my $one = Chalk::IR::Node::ConstantF->new(value => 1.0);

    # Test idealize() directly (not peephole which does constant folding first)
    # x * 1.0 = x
    my $mul1 = Chalk::IR::Node::MulF->new(left => $x, right => $one);
    my $result1 = $mul1->idealize();
    ok($result1, 'idealize returns a result for x * 1.0');
    is($result1->id, $x->id, 'x * 1.0 = x (identity right)');

    # 1.0 * x = x
    my $mul2 = Chalk::IR::Node::MulF->new(left => $one, right => $x);
    my $result2 = $mul2->idealize();
    ok($result2, 'idealize returns a result for 1.0 * x');
    is($result2->id, $x->id, '1.0 * x = x (identity left)');
};

subtest 'MulF idealize zero absorption: x * 0.0 = 0.0' => sub {
    my $x = Chalk::IR::Node::ConstantF->new(value => 5.5);
    my $zero = Chalk::IR::Node::ConstantF->new(value => 0.0);

    # x * 0.0 = 0.0 (only when both are constant to preserve side effects)
    my $mul1 = Chalk::IR::Node::MulF->new(left => $x, right => $zero);
    my $result1 = $mul1->idealize();
    ok($result1, 'idealize returns a result for x * 0.0');
    isa_ok($result1, 'Chalk::IR::Node::ConstantF', 'x * 0.0 = 0.0 (zero absorption right)');
    is($result1->value, 0.0, 'value is 0.0');

    # 0.0 * x = 0.0 (only when both are constant to preserve side effects)
    my $mul2 = Chalk::IR::Node::MulF->new(left => $zero, right => $x);
    my $result2 = $mul2->idealize();
    ok($result2, 'idealize returns a result for 0.0 * x');
    isa_ok($result2, 'Chalk::IR::Node::ConstantF', '0.0 * x = 0.0 (zero absorption left)');
    is($result2->value, 0.0, 'value is 0.0');
};

done_testing();
