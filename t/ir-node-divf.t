#!/usr/bin/env perl
# ABOUTME: Tests for DivF IR node (floating-point division)
# ABOUTME: Verifies float division node behavior, peephole optimizations, and type computation

use 5.42.0;
use utf8;
use Test::More;
use experimental qw(class);

# Load required modules
use Chalk::IR::Node::DivF;
use Chalk::IR::Node::ConstantF;
use Chalk::IR::Type::Float;

# ============================================================
# DivF node creation and basic properties
# ============================================================

subtest 'DivF node creation' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 7.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $div = Chalk::IR::Node::DivF->new(left => $left, right => $right);

    ok($div, 'DivF node created');
    is($div->op, 'DivF', 'op is DivF');
    ok($div->id, 'node has ID');
    is($div->left->id, $left->id, 'left accessor works');
    is($div->right->id, $right->id, 'right accessor works');
};

subtest 'DivF node requires operands' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 1.0);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.0);

    eval { Chalk::IR::Node::DivF->new(left => $left) };
    like($@, qr/right.*is (required|missing)/i, 'dies without right operand');

    eval { Chalk::IR::Node::DivF->new(right => $right) };
    like($@, qr/left.*is (required|missing)/i, 'dies without left operand');
};

# ============================================================
# Node properties
# ============================================================

subtest 'DivF inputs()' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 7.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $div = Chalk::IR::Node::DivF->new(left => $left, right => $right);

    my $inputs = $div->inputs();
    is(ref($inputs), 'ARRAY', 'inputs returns array ref');
    is(scalar(@$inputs), 2, 'DivF has two inputs');
    is($inputs->[0], $left->id, 'first input is left operand ID');
    is($inputs->[1], $right->id, 'second input is right operand ID');
};

# ============================================================
# Type computation
# ============================================================

subtest 'DivF compute() returns TypeFloat' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 7.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $div = Chalk::IR::Node::DivF->new(left => $left, right => $right);

    my $type = $div->compute();
    isa_ok($type, 'Chalk::IR::Type::Float', 'compute() returns TypeFloat');
    ok($type->is_constant(), 'type is constant when both operands are constant');
    is($type->value, 3.0, 'constant folding: 7.5 / 2.5 = 3.0');
};

subtest 'DivF compute() constant folding' => sub {
    my $div1 = Chalk::IR::Node::DivF->new(
        left => Chalk::IR::Node::ConstantF->new(value => 7.5),
        right => Chalk::IR::Node::ConstantF->new(value => 2.5)
    );
    is($div1->compute()->value, 3.0, '7.5 / 2.5 = 3.0');

    my $div2 = Chalk::IR::Node::DivF->new(
        left => Chalk::IR::Node::ConstantF->new(value => 9.0),
        right => Chalk::IR::Node::ConstantF->new(value => 3.0)
    );
    is($div2->compute()->value, 3.0, '9.0 / 3.0 = 3.0');

    my $div3 = Chalk::IR::Node::DivF->new(
        left => Chalk::IR::Node::ConstantF->new(value => 5.5),
        right => Chalk::IR::Node::ConstantF->new(value => 1.0)
    );
    is($div3->compute()->value, 5.5, '5.5 / 1.0 = 5.5');

    my $div4 = Chalk::IR::Node::DivF->new(
        left => Chalk::IR::Node::ConstantF->new(value => 0.0),
        right => Chalk::IR::Node::ConstantF->new(value => 5.5)
    );
    is($div4->compute()->value, 0.0, '0.0 / 5.5 = 0.0');
};

subtest 'DivF compute() division by zero' => sub {
    my $div = Chalk::IR::Node::DivF->new(
        left => Chalk::IR::Node::ConstantF->new(value => 5.5),
        right => Chalk::IR::Node::ConstantF->new(value => 0.0)
    );

    # Division by zero should NOT be constant folded - leave for runtime
    my $type = $div->compute();
    ok(!$type->is_constant(), 'division by zero is not constant folded');
    isa_ok($type, 'Chalk::IR::Type::Float', 'returns Float type');
};

# ============================================================
# Execution
# ============================================================

subtest 'DivF execute()' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 7.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $div = Chalk::IR::Node::DivF->new(left => $left, right => $right);

    # Create a simple context that returns node values
    my $context = sub {
        my $key = shift;
        if ($key eq "node:" . $left->id) { return 7.5; }
        if ($key eq "node:" . $right->id) { return 2.5; }
        die "Unknown node: $key";
    };

    is($div->execute($context), 3.0, 'execute() returns 7.5 / 2.5 = 3.0');
};

# ============================================================
# Serialization
# ============================================================

subtest 'DivF to_hash()' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 7.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $div = Chalk::IR::Node::DivF->new(left => $left, right => $right);

    my $hash = $div->to_hash();
    is($hash->{op}, 'DivF', 'op is DivF');
    is($hash->{id}, $div->id, 'id matches');
    is(ref($hash->{inputs}), 'ARRAY', 'inputs is array');
    is(scalar(@{$hash->{inputs}}), 2, 'two inputs');
    is($hash->{attributes}{left_id}, $left->id, 'left_id in attributes');
    is($hash->{attributes}{right_id}, $right->id, 'right_id in attributes');
};

# ============================================================
# Peephole optimizations
# ============================================================

subtest 'DivF peephole constant folding' => sub {
    my $div = Chalk::IR::Node::DivF->new(
        left => Chalk::IR::Node::ConstantF->new(value => 7.5),
        right => Chalk::IR::Node::ConstantF->new(value => 2.5)
    );

    my $result = $div->peephole();
    isa_ok($result, 'Chalk::IR::Node::ConstantF', 'constant folding produces ConstantF');
    is($result->value, 3.0, 'folded to constant 3.0');
};

subtest 'DivF idealize identity: x / 1.0 = x' => sub {
    my $x = Chalk::IR::Node::ConstantF->new(value => 5.5);
    my $one = Chalk::IR::Node::ConstantF->new(value => 1.0);

    # Test idealize() directly (not peephole which does constant folding first)
    # x / 1.0 = x (right identity)
    my $div1 = Chalk::IR::Node::DivF->new(left => $x, right => $one);
    my $result1 = $div1->idealize();
    ok($result1, 'idealize returns a result for x / 1.0');
    is($result1->id, $x->id, 'x / 1.0 = x (identity right)');

    # 1.0 / x ≠ x (no left identity for division)
    my $div2 = Chalk::IR::Node::DivF->new(left => $one, right => $x);
    my $result2 = $div2->idealize();
    ok(!$result2, 'idealize returns nothing for 1.0 / x (no left identity)');
};

subtest 'DivF idealize zero numerator: 0.0 / x = 0.0' => sub {
    my $zero = Chalk::IR::Node::ConstantF->new(value => 0.0);
    my $x = Chalk::IR::Node::ConstantF->new(value => 5.5);

    # 0.0 / x = 0.0 (where x != 0)
    my $div = Chalk::IR::Node::DivF->new(left => $zero, right => $x);
    my $result = $div->idealize();
    ok($result, 'idealize returns a result for 0.0 / x');
    isa_ok($result, 'Chalk::IR::Node::ConstantF', '0.0 / x produces ConstantF');
    is($result->value, 0.0, '0.0 / 5.5 = 0.0');
};

subtest 'DivF idealize no optimization for x / 0.0' => sub {
    my $x = Chalk::IR::Node::ConstantF->new(value => 5.5);
    my $zero = Chalk::IR::Node::ConstantF->new(value => 0.0);

    # x / 0.0 should NOT be optimized (leave for runtime error)
    my $div = Chalk::IR::Node::DivF->new(left => $x, right => $zero);
    my $result = $div->idealize();
    ok(!$result, 'idealize returns nothing for x / 0.0 (division by zero)');
};

subtest 'DivF idealize no optimization for 0.0 / 0.0' => sub {
    my $zero = Chalk::IR::Node::ConstantF->new(value => 0.0);

    # 0.0 / 0.0 should NOT be optimized (indeterminate form)
    my $div = Chalk::IR::Node::DivF->new(left => $zero, right => $zero);
    my $result = $div->idealize();
    ok(!$result, 'idealize returns nothing for 0.0 / 0.0 (indeterminate)');
};

subtest 'DivF peephole integration: identity' => sub {
    my $x = Chalk::IR::Node::ConstantF->new(value => 5.5);
    my $one = Chalk::IR::Node::ConstantF->new(value => 1.0);
    my $div = Chalk::IR::Node::DivF->new(left => $x, right => $one);

    my $result = $div->peephole();
    # Since both are constants, it will constant fold instead
    isa_ok($result, 'Chalk::IR::Node::ConstantF', 'constant folding takes precedence');
    is($result->value, 5.5, 'peephole: 5.5 / 1.0 = 5.5');
};

done_testing();
