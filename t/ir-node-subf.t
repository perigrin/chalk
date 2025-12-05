#!/usr/bin/env perl
# ABOUTME: Tests for SubF IR node (floating-point subtraction)
# ABOUTME: Verifies float subtraction node behavior, peephole optimizations, and type computation

use 5.42.0;
use utf8;
use Test::More;
use experimental qw(class);

# Load required modules
use Chalk::IR::Node::SubF;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Float;

# ============================================================
# SubF node creation and basic properties
# ============================================================

subtest 'SubF node creation' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(5.5),
        value => 5.5,
    );
    my $right = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $sub = Chalk::IR::Node::SubF->new(left => $left, right => $right);

    ok($sub, 'SubF node created');
    is($sub->op, 'SubF', 'op is SubF');
    ok($sub->id, 'node has ID');
    is($sub->left->id, $left->id, 'left accessor works');
    is($sub->right->id, $right->id, 'right accessor works');
};

subtest 'SubF node requires operands' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(1.0),
        value => 1.0,
    );
    my $right = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.0),
        value => 2.0,
    );

    eval { Chalk::IR::Node::SubF->new(left => $left) };
    like($@, qr/right.*is (required|missing)/i, 'dies without right operand');

    eval { Chalk::IR::Node::SubF->new(right => $right) };
    like($@, qr/left.*is (required|missing)/i, 'dies without left operand');
};

# ============================================================
# Node properties
# ============================================================

subtest 'SubF inputs()' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(5.5),
        value => 5.5,
    );
    my $right = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $sub = Chalk::IR::Node::SubF->new(left => $left, right => $right);

    my $inputs = $sub->inputs();
    is(ref($inputs), 'ARRAY', 'inputs returns array ref');
    is(scalar(@$inputs), 2, 'SubF has two inputs');
    is($inputs->[0], $left->id, 'first input is left operand ID');
    is($inputs->[1], $right->id, 'second input is right operand ID');
};

# ============================================================
# Type computation
# ============================================================

subtest 'SubF compute() returns TypeFloat' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(5.5),
        value => 5.5,
    );
    my $right = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $sub = Chalk::IR::Node::SubF->new(left => $left, right => $right);

    my $type = $sub->compute();
    isa_ok($type, 'Chalk::IR::Type::Float', 'compute() returns TypeFloat');
    ok($type->is_constant(), 'type is constant when both operands are constant');
    is($type->value, 3.0, 'constant folding: 5.5 - 2.5 = 3.0');
};

subtest 'SubF compute() constant folding' => sub {
    my $sub1 = Chalk::IR::Node::SubF->new(
        left => Chalk::IR::Node::Constant->new(
            type => Chalk::IR::Type::Float->constant(5.5),
            value => 5.5,
        ),
        right => Chalk::IR::Node::Constant->new(
            type => Chalk::IR::Type::Float->constant(2.5),
            value => 2.5,
        )
    );
    is($sub1->compute()->value, 3.0, '5.5 - 2.5 = 3.0');

    my $sub2 = Chalk::IR::Node::SubF->new(
        left => Chalk::IR::Node::Constant->new(
            type => Chalk::IR::Type::Float->constant(1.5),
            value => 1.5,
        ),
        right => Chalk::IR::Node::Constant->new(
            type => Chalk::IR::Type::Float->constant(1.5),
            value => 1.5,
        )
    );
    is($sub2->compute()->value, 0.0, '1.5 - 1.5 = 0.0');

    my $sub3 = Chalk::IR::Node::SubF->new(
        left => Chalk::IR::Node::Constant->new(
            type => Chalk::IR::Type::Float->constant(5.5),
            value => 5.5,
        ),
        right => Chalk::IR::Node::Constant->new(
            type => Chalk::IR::Type::Float->constant(0.0),
            value => 0.0,
        )
    );
    is($sub3->compute()->value, 5.5, '5.5 - 0.0 = 5.5');

    my $sub4 = Chalk::IR::Node::SubF->new(
        left => Chalk::IR::Node::Constant->new(
            type => Chalk::IR::Type::Float->constant(0.0),
            value => 0.0,
        ),
        right => Chalk::IR::Node::Constant->new(
            type => Chalk::IR::Type::Float->constant(5.5),
            value => 5.5,
        )
    );
    is($sub4->compute()->value, -5.5, '0.0 - 5.5 = -5.5');
};

# ============================================================
# Execution
# ============================================================

subtest 'SubF execute()' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(5.5),
        value => 5.5,
    );
    my $right = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $sub = Chalk::IR::Node::SubF->new(left => $left, right => $right);

    # Create a simple context that returns node values
    my $context = sub {
        my $key = shift;
        if ($key eq "node:" . $left->id) { return 5.5; }
        if ($key eq "node:" . $right->id) { return 2.5; }
        die "Unknown node: $key";
    };

    is($sub->execute($context), 3.0, 'execute() returns 5.5 - 2.5 = 3.0');
};

# ============================================================
# Serialization
# ============================================================

subtest 'SubF to_hash()' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(5.5),
        value => 5.5,
    );
    my $right = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $sub = Chalk::IR::Node::SubF->new(left => $left, right => $right);

    my $hash = $sub->to_hash();
    is($hash->{op}, 'SubF', 'op is SubF');
    is($hash->{id}, $sub->id, 'id matches');
    is(ref($hash->{inputs}), 'ARRAY', 'inputs is array');
    is(scalar(@{$hash->{inputs}}), 2, 'two inputs');
    is($hash->{attributes}{left_id}, $left->id, 'left_id in attributes');
    is($hash->{attributes}{right_id}, $right->id, 'right_id in attributes');
};

# ============================================================
# Peephole optimizations
# ============================================================

subtest 'SubF peephole constant folding' => sub {
    my $sub = Chalk::IR::Node::SubF->new(
        left => Chalk::IR::Node::Constant->new(
            type => Chalk::IR::Type::Float->constant(5.5),
            value => 5.5,
        ),
        right => Chalk::IR::Node::Constant->new(
            type => Chalk::IR::Type::Float->constant(2.5),
            value => 2.5,
        )
    );

    my $result = $sub->peephole();
    isa_ok($result, 'Chalk::IR::Node::Constant', 'constant folding produces Constant');
    is($result->value, 3.0, 'folded to constant 3.0');
};

subtest 'SubF idealize identity: x - 0.0 = x' => sub {
    my $x = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(5.5),
        value => 5.5,
    );
    my $zero = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(0.0),
        value => 0.0,
    );

    # Test idealize() directly (not peephole which does constant folding first)
    # x - 0.0 = x (right identity)
    my $sub1 = Chalk::IR::Node::SubF->new(left => $x, right => $zero);
    my $result1 = $sub1->idealize();
    ok($result1, 'idealize returns a result for x - 0.0');
    is($result1->id, $x->id, 'x - 0.0 = x (identity right)');

    # 0.0 - x ≠ x (no left identity for subtraction)
    my $sub2 = Chalk::IR::Node::SubF->new(left => $zero, right => $x);
    my $result2 = $sub2->idealize();
    ok(!$result2, 'idealize returns nothing for 0.0 - x (no left identity)');
};

subtest 'SubF idealize self-subtraction: x - x = 0.0' => sub {
    my $x = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(5.5),
        value => 5.5,
    );

    # x - x = 0.0
    my $sub = Chalk::IR::Node::SubF->new(left => $x, right => $x);
    my $result = $sub->idealize();
    ok($result, 'idealize returns a result for x - x');
    isa_ok($result, 'Chalk::IR::Node::Constant', 'x - x produces Constant');
    is($result->value, 0.0, 'x - x = 0.0');
};

subtest 'SubF peephole integration: self-subtraction' => sub {
    my $x = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(5.5),
        value => 5.5,
    );
    my $sub = Chalk::IR::Node::SubF->new(left => $x, right => $x);

    my $result = $sub->peephole();
    isa_ok($result, 'Chalk::IR::Node::Constant', 'self-subtraction produces Constant');
    is($result->value, 0.0, 'peephole: x - x = 0.0');
};

done_testing();
