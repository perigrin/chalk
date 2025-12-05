#!/usr/bin/env perl
# ABOUTME: Tests for LTF IR node (floating-point less-than comparison)
# ABOUTME: Verifies float less-than comparison, peephole optimizations, and type computation

use 5.42.0;
use utf8;
use Test::More;
use experimental qw(class);

# Load required modules
use Chalk::IR::Node::LTF;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Float;
use Chalk::IR::Type::Integer;

# ============================================================
# LTF node creation and basic properties
# ============================================================

subtest 'LTF node creation' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $right = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(3.5),
        value => 3.5,
    );
    my $lt = Chalk::IR::Node::LTF->new(left => $left, right => $right);

    ok($lt, 'LTF node created');
    is($lt->op, 'LTF', 'op is LTF');
    ok($lt->id, 'node has ID');
    is($lt->left->id, $left->id, 'left accessor works');
    is($lt->right->id, $right->id, 'right accessor works');
};

# ============================================================
# Node properties
# ============================================================

subtest 'LTF inputs()' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(1.5),
        value => 1.5,
    );
    my $right = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $lt = Chalk::IR::Node::LTF->new(left => $left, right => $right);

    my $inputs = $lt->inputs();
    is(ref($inputs), 'ARRAY', 'inputs returns array ref');
    is(scalar(@$inputs), 2, 'LTF has two inputs');
    is($inputs->[0], $left->id, 'first input is left operand ID');
    is($inputs->[1], $right->id, 'second input is right operand ID');
};

# ============================================================
# Type computation
# ============================================================

subtest 'LTF compute() returns TypeInteger' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $right = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(3.0),
        value => 3.0,
    );
    my $lt = Chalk::IR::Node::LTF->new(left => $left, right => $right);

    my $type = $lt->compute();
    isa_ok($type, 'Chalk::IR::Type::Integer', 'compute() returns TypeInteger');
    ok($type->is_constant(), 'type is constant when both operands are constant');
    is($type->value, 1, 'constant folding: 2.5 < 3.0 = 1');
};

subtest 'LTF compute() constant folding' => sub {
    my $lt1 = Chalk::IR::Node::LTF->new(
        left => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    ),
        right => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(3.0),
        value => 3.0,
    )
    );
    is($lt1->compute()->value, 1, '2.5 < 3.0 = 1');

    my $lt2 = Chalk::IR::Node::LTF->new(
        left => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(3.0),
        value => 3.0,
    ),
        right => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    )
    );
    is($lt2->compute()->value, 0, '3.0 < 2.5 = 0');

    my $lt3 = Chalk::IR::Node::LTF->new(
        left => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    ),
        right => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    )
    );
    is($lt3->compute()->value, 0, '2.5 < 2.5 = 0 (equal values)');

    my $lt4 = Chalk::IR::Node::LTF->new(
        left => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(0.0),
        value => 0.0,
    ),
        right => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(1.0),
        value => 1.0,
    )
    );
    is($lt4->compute()->value, 1, '0.0 < 1.0 = 1');

    my $lt5 = Chalk::IR::Node::LTF->new(
        left => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(-1.5),
        value => -1.5,
    ),
        right => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(0.0),
        value => 0.0,
    )
    );
    is($lt5->compute()->value, 1, '-1.5 < 0.0 = 1');
};

# ============================================================
# Execution
# ============================================================

subtest 'LTF execute()' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $right = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(3.5),
        value => 3.5,
    );
    my $lt = Chalk::IR::Node::LTF->new(left => $left, right => $right);

    # Create a simple context that returns node values
    my $context = sub {
        my $key = shift;
        if ($key eq "node:" . $left->id) { return 2.5; }
        if ($key eq "node:" . $right->id) { return 3.5; }
        die "Unknown node: $key";
    };

    is($lt->execute($context), 1, 'execute() returns 2.5 < 3.5 = 1');

    # Test with different values
    my $left2 = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(3.5),
        value => 3.5,
    );
    my $right2 = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $lt2 = Chalk::IR::Node::LTF->new(left => $left2, right => $right2);

    my $context2 = sub {
        my $key = shift;
        if ($key eq "node:" . $left2->id) { return 3.5; }
        if ($key eq "node:" . $right2->id) { return 2.5; }
        die "Unknown node: $key";
    };

    is($lt2->execute($context2), 0, 'execute() returns 3.5 < 2.5 = 0');
};

# ============================================================
# Serialization
# ============================================================

subtest 'LTF to_hash()' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(1.5),
        value => 1.5,
    );
    my $right = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    );
    my $lt = Chalk::IR::Node::LTF->new(left => $left, right => $right);

    my $hash = $lt->to_hash();
    is($hash->{op}, 'LTF', 'op is LTF');
    is($hash->{id}, $lt->id, 'id matches');
    is(ref($hash->{inputs}), 'ARRAY', 'inputs is array');
    is(scalar(@{$hash->{inputs}}), 2, 'two inputs');
    is($hash->{attributes}{left_id}, $left->id, 'left_id in attributes');
    is($hash->{attributes}{right_id}, $right->id, 'right_id in attributes');
};

# ============================================================
# Peephole optimizations
# ============================================================

subtest 'LTF peephole constant folding true case' => sub {
    my $lt = Chalk::IR::Node::LTF->new(
        left => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    ),
        right => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(3.0),
        value => 3.0,
    )
    );

    my $result = $lt->peephole();
    isa_ok($result, 'Chalk::IR::Node::Constant', 'constant folding produces Constant (integer)');
    is($result->value, 1, 'folded to constant 1');
    isa_ok($result->type, 'Chalk::IR::Type::Integer', 'result type is Integer');
};

subtest 'LTF peephole constant folding false case' => sub {
    my $lt = Chalk::IR::Node::LTF->new(
        left => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(3.0),
        value => 3.0,
    ),
        right => Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(2.5),
        value => 2.5,
    )
    );

    my $result = $lt->peephole();
    isa_ok($result, 'Chalk::IR::Node::Constant', 'constant folding produces Constant (integer)');
    is($result->value, 0, 'folded to constant 0');
    isa_ok($result->type, 'Chalk::IR::Type::Integer', 'result type is Integer');
};

subtest 'LTF idealize self-comparison: x < x = 0' => sub {
    my $x = Chalk::IR::Node::Constant->new(
        type => Chalk::IR::Type::Float->constant(5.5),
        value => 5.5,
    );

    # Test idealize() directly for x < x = 0
    my $lt = Chalk::IR::Node::LTF->new(left => $x, right => $x);
    my $result = $lt->idealize();
    ok($result, 'idealize returns a result for x < x');
    isa_ok($result, 'Chalk::IR::Node::Constant', 'x < x produces Constant');
    is($result->value, 0, 'x < x = 0 (self-comparison, nothing is less than itself)');
    isa_ok($result->type, 'Chalk::IR::Type::Integer', 'result type is Integer');
};

done_testing();
