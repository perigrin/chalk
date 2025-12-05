#!/usr/bin/env perl
# ABOUTME: Tests for EQF IR node (floating-point equality comparison)
# ABOUTME: Verifies float equality comparison, peephole optimizations, and type computation

use 5.42.0;
use utf8;
use Test::More;
use experimental qw(class);

# Load required modules
use Chalk::IR::Node::EQF;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Float;
use Chalk::IR::Type::Integer;

# ============================================================
# EQF node creation and basic properties
# ============================================================

subtest 'EQF node creation' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $right = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(3.5),
        value => 3.5,
    );
    my $eq = Chalk::IR::Node::EQF->new(left => $left, right => $right);

    ok($eq, 'EQF node created');
    is($eq->op, 'EQF', 'op is EQF');
    ok($eq->id, 'node has ID');
    is($eq->left->id, $left->id, 'left accessor works');
    is($eq->right->id, $right->id, 'right accessor works');
};

# ============================================================
# Node properties
# ============================================================

subtest 'EQF inputs()' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(1.5),
        value => 1.5,
    );
    my $right = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $eq = Chalk::IR::Node::EQF->new(left => $left, right => $right);

    my $inputs = $eq->inputs();
    is(ref($inputs), 'ARRAY', 'inputs returns array ref');
    is(scalar(@$inputs), 2, 'EQF has two inputs');
    is($inputs->[0], $left->id, 'first input is left operand ID');
    is($inputs->[1], $right->id, 'second input is right operand ID');
};

# ============================================================
# Type computation
# ============================================================

subtest 'EQF compute() returns TypeInteger' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $right = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $eq = Chalk::IR::Node::EQF->new(left => $left, right => $right);

    my $type = $eq->compute();
    isa_ok($type, 'Chalk::IR::Type::Integer', 'compute() returns TypeInteger');
    ok($type->is_constant(), 'type is constant when both operands are constant');
    is($type->value, 1, 'constant folding: 2.5 == 2.5 = 1');
};

subtest 'EQF compute() constant folding' => sub {
    my $eq1 = Chalk::IR::Node::EQF->new(
        left => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    ),
        right => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    )
    );
    is($eq1->compute()->value, 1, '2.5 == 2.5 = 1');

    my $eq2 = Chalk::IR::Node::EQF->new(
        left => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    ),
        right => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(3.0),
        value => 3.0,
    )
    );
    is($eq2->compute()->value, 0, '2.5 == 3.0 = 0');

    my $eq3 = Chalk::IR::Node::EQF->new(
        left => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(0.0),
        value => 0.0,
    ),
        right => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(0.0),
        value => 0.0,
    )
    );
    is($eq3->compute()->value, 1, '0.0 == 0.0 = 1');
};

# ============================================================
# Execution
# ============================================================

subtest 'EQF execute()' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $right = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $eq = Chalk::IR::Node::EQF->new(left => $left, right => $right);

    # Create a simple context that returns node values
    my $context = sub {
        my $key = shift;
        if ($key eq "node:" . $left->id) { return 2.5; }
        if ($key eq "node:" . $right->id) { return 2.5; }
        die "Unknown node: $key";
    };

    is($eq->execute($context), 1, 'execute() returns 2.5 == 2.5 = 1');

    # Test with different values
    my $left2 = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $right2 = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(3.5),
        value => 3.5,
    );
    my $eq2 = Chalk::IR::Node::EQF->new(left => $left2, right => $right2);

    my $context2 = sub {
        my $key = shift;
        if ($key eq "node:" . $left2->id) { return 2.5; }
        if ($key eq "node:" . $right2->id) { return 3.5; }
        die "Unknown node: $key";
    };

    is($eq2->execute($context2), 0, 'execute() returns 2.5 == 3.5 = 0');
};

# ============================================================
# Serialization
# ============================================================

subtest 'EQF to_hash()' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(1.5),
        value => 1.5,
    );
    my $right = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $eq = Chalk::IR::Node::EQF->new(left => $left, right => $right);

    my $hash = $eq->to_hash();
    is($hash->{op}, 'EQF', 'op is EQF');
    is($hash->{id}, $eq->id, 'id matches');
    is(ref($hash->{inputs}), 'ARRAY', 'inputs is array');
    is(scalar(@{$hash->{inputs}}), 2, 'two inputs');
    is($hash->{attributes}{left_id}, $left->id, 'left_id in attributes');
    is($hash->{attributes}{right_id}, $right->id, 'right_id in attributes');
};

# ============================================================
# Peephole optimizations
# ============================================================

subtest 'EQF peephole constant folding' => sub {
    my $eq = Chalk::IR::Node::EQF->new(
        left => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    ),
        right => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    )
    );

    my $result = $eq->peephole();
    isa_ok($result, 'Chalk::IR::Node::Constant', 'constant folding produces Constant (integer)');
    is($result->value, 1, 'folded to constant 1');
    isa_ok($result->type, 'Chalk::IR::Type::Integer', 'result type is Integer');
};

subtest 'EQF peephole constant folding false case' => sub {
    my $eq = Chalk::IR::Node::EQF->new(
        left => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    ),
        right => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(3.0),
        value => 3.0,
    )
    );

    my $result = $eq->peephole();
    isa_ok($result, 'Chalk::IR::Node::Constant', 'constant folding produces Constant (integer)');
    is($result->value, 0, 'folded to constant 0');
    isa_ok($result->type, 'Chalk::IR::Type::Integer', 'result type is Integer');
};

subtest 'EQF idealize self-comparison: x == x = 1' => sub {
    my $x = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(5.5),
        value => 5.5,
    );

    # Test idealize() directly for x == x = 1
    my $eq = Chalk::IR::Node::EQF->new(left => $x, right => $x);
    my $result = $eq->idealize();
    ok($result, 'idealize returns a result for x == x');
    isa_ok($result, 'Chalk::IR::Node::Constant', 'x == x produces Constant');
    is($result->value, 1, 'x == x = 1 (self-comparison)');
    isa_ok($result->type, 'Chalk::IR::Type::Integer', 'result type is Integer');
};

done_testing();
