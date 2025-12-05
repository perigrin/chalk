#!/usr/bin/env perl
# ABOUTME: Tests for AddF IR node (floating-point addition)
# ABOUTME: Verifies float addition node behavior, peephole optimizations, and type computation

use 5.42.0;
use utf8;
use Test::More;
use experimental qw(class);

# Load required modules
use Chalk::IR::Node::AddF;
use Chalk::IR::Node::ConstantF;
use Chalk::IR::Type::Float;

# ============================================================
# AddF node creation and basic properties
# ============================================================

subtest 'AddF node creation' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 3.5);
    my $add = Chalk::IR::Node::AddF->new(left => $left, right => $right);

    ok($add, 'AddF node created');
    is($add->op, 'AddF', 'op is AddF');
    ok($add->id, 'node has ID');
    is($add->left->id, $left->id, 'left accessor works');
    is($add->right->id, $right->id, 'right accessor works');
};

subtest 'AddF node requires operands' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 1.0);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.0);

    eval { Chalk::IR::Node::AddF->new(left => $left) };
    like($@, qr/right.*is (required|missing)/i, 'dies without right operand');

    eval { Chalk::IR::Node::AddF->new(right => $right) };
    like($@, qr/left.*is (required|missing)/i, 'dies without left operand');
};

# ============================================================
# Node properties
# ============================================================

subtest 'AddF inputs()' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 1.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $add = Chalk::IR::Node::AddF->new(left => $left, right => $right);

    my $inputs = $add->inputs();
    is(ref($inputs), 'ARRAY', 'inputs returns array ref');
    is(scalar(@$inputs), 2, 'AddF has two inputs');
    is($inputs->[0], $left->id, 'first input is left operand ID');
    is($inputs->[1], $right->id, 'second input is right operand ID');
};

# ============================================================
# Type computation
# ============================================================

subtest 'AddF compute() returns TypeFloat' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 1.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $add = Chalk::IR::Node::AddF->new(left => $left, right => $right);

    my $type = $add->compute();
    isa_ok($type, 'Chalk::IR::Type::Float', 'compute() returns TypeFloat');
    ok($type->is_constant(), 'type is constant when both operands are constant');
    is($type->value, 4.0, 'constant folding: 1.5 + 2.5 = 4.0');
};

subtest 'AddF compute() constant folding' => sub {
    my $add1 = Chalk::IR::Node::AddF->new(
        left => Chalk::IR::Node::ConstantF->new(value => 2.5),
        right => Chalk::IR::Node::ConstantF->new(value => 3.5)
    );
    is($add1->compute()->value, 6.0, '2.5 + 3.5 = 6.0');

    my $add2 = Chalk::IR::Node::AddF->new(
        left => Chalk::IR::Node::ConstantF->new(value => -1.5),
        right => Chalk::IR::Node::ConstantF->new(value => 1.5)
    );
    is($add2->compute()->value, 0.0, '-1.5 + 1.5 = 0.0');

    my $add3 = Chalk::IR::Node::AddF->new(
        left => Chalk::IR::Node::ConstantF->new(value => 0.0),
        right => Chalk::IR::Node::ConstantF->new(value => 5.5)
    );
    is($add3->compute()->value, 5.5, '0.0 + 5.5 = 5.5');
};

# ============================================================
# Execution
# ============================================================

subtest 'AddF execute()' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 3.5);
    my $add = Chalk::IR::Node::AddF->new(left => $left, right => $right);

    # Create a simple context that returns node values
    my $context = sub {
        my $key = shift;
        if ($key eq "node:" . $left->id) { return 2.5; }
        if ($key eq "node:" . $right->id) { return 3.5; }
        die "Unknown node: $key";
    };

    is($add->execute($context), 6.0, 'execute() returns 2.5 + 3.5 = 6.0');
};

# ============================================================
# Serialization
# ============================================================

subtest 'AddF to_hash()' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 1.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $add = Chalk::IR::Node::AddF->new(left => $left, right => $right);

    my $hash = $add->to_hash();
    is($hash->{op}, 'AddF', 'op is AddF');
    is($hash->{id}, $add->id, 'id matches');
    is(ref($hash->{inputs}), 'ARRAY', 'inputs is array');
    is(scalar(@{$hash->{inputs}}), 2, 'two inputs');
    is($hash->{attributes}{left_id}, $left->id, 'left_id in attributes');
    is($hash->{attributes}{right_id}, $right->id, 'right_id in attributes');
};

# ============================================================
# Peephole optimizations
# ============================================================

subtest 'AddF peephole constant folding' => sub {
    my $add = Chalk::IR::Node::AddF->new(
        left => Chalk::IR::Node::ConstantF->new(value => 2.5),
        right => Chalk::IR::Node::ConstantF->new(value => 3.5)
    );

    my $result = $add->peephole();
    isa_ok($result, 'Chalk::IR::Node::ConstantF', 'constant folding produces ConstantF');
    is($result->value, 6.0, 'folded to constant 6.0');
};

subtest 'AddF idealize identity: x + 0.0 = x' => sub {
    my $x = Chalk::IR::Node::ConstantF->new(value => 5.5);
    my $zero = Chalk::IR::Node::ConstantF->new(value => 0.0);

    # Test idealize() directly (not peephole which does constant folding first)
    # x + 0.0 = x
    my $add1 = Chalk::IR::Node::AddF->new(left => $x, right => $zero);
    my $result1 = $add1->idealize();
    ok($result1, 'idealize returns a result for x + 0.0');
    is($result1->id, $x->id, 'x + 0.0 = x (identity right)');

    # 0.0 + x = x
    my $add2 = Chalk::IR::Node::AddF->new(left => $zero, right => $x);
    my $result2 = $add2->idealize();
    ok($result2, 'idealize returns a result for 0.0 + x');
    is($result2->id, $x->id, '0.0 + x = x (identity left)');
};

done_testing();
