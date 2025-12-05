#!/usr/bin/env perl
# ABOUTME: Tests for MinusF IR node (floating-point unary negation)
# ABOUTME: Verifies float negation node behavior, peephole optimizations, and type computation

use 5.42.0;
use utf8;
use Test::More;
use experimental qw(class);

# Load required modules
use Chalk::IR::Node::MinusF;
use Chalk::IR::Node::ConstantF;
use Chalk::IR::Type::Float;

# ============================================================
# MinusF node creation and basic properties
# ============================================================

subtest 'MinusF node creation' => sub {
    my $operand = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $minus = Chalk::IR::Node::MinusF->new(operand => $operand);

    ok($minus, 'MinusF node created');
    is($minus->op, 'MinusF', 'op is MinusF');
    ok($minus->id, 'node has ID');
    is($minus->operand->id, $operand->id, 'operand accessor works');
};

subtest 'MinusF node requires operand' => sub {
    eval { Chalk::IR::Node::MinusF->new() };
    like($@, qr/operand.*is (required|missing)/i, 'dies without operand');
};

# ============================================================
# Node properties
# ============================================================

subtest 'MinusF inputs()' => sub {
    my $operand = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $minus = Chalk::IR::Node::MinusF->new(operand => $operand);

    my $inputs = $minus->inputs();
    is(ref($inputs), 'ARRAY', 'inputs returns array ref');
    is(scalar(@$inputs), 1, 'MinusF has one input (unary operation)');
    is($inputs->[0], $operand->id, 'input is operand ID');
};

# ============================================================
# Type computation
# ============================================================

subtest 'MinusF compute() returns TypeFloat' => sub {
    my $operand = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $minus = Chalk::IR::Node::MinusF->new(operand => $operand);

    my $type = $minus->compute();
    isa_ok($type, 'Chalk::IR::Type::Float', 'compute() returns TypeFloat');
    ok($type->is_constant(), 'type is constant when operand is constant');
    is($type->value, -2.5, 'constant folding: -2.5 = -2.5');
};

subtest 'MinusF compute() constant folding' => sub {
    my $minus1 = Chalk::IR::Node::MinusF->new(
        operand => Chalk::IR::Node::ConstantF->new(value => 2.5)
    );
    is($minus1->compute()->value, -2.5, '-2.5 = -2.5');

    my $minus2 = Chalk::IR::Node::MinusF->new(
        operand => Chalk::IR::Node::ConstantF->new(value => -3.5)
    );
    is($minus2->compute()->value, 3.5, '-(-3.5) = 3.5');

    my $minus3 = Chalk::IR::Node::MinusF->new(
        operand => Chalk::IR::Node::ConstantF->new(value => 0.0)
    );
    is($minus3->compute()->value, 0.0, '-0.0 = 0.0');
};

# ============================================================
# Execution
# ============================================================

subtest 'MinusF execute()' => sub {
    my $operand = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $minus = Chalk::IR::Node::MinusF->new(operand => $operand);

    # Create a simple context that returns node values
    my $context = sub {
        my $key = shift;
        if ($key eq "node:" . $operand->id) { return 2.5; }
        die "Unknown node: $key";
    };

    is($minus->execute($context), -2.5, 'execute() returns -2.5');
};

# ============================================================
# Serialization
# ============================================================

subtest 'MinusF to_hash()' => sub {
    my $operand = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $minus = Chalk::IR::Node::MinusF->new(operand => $operand);

    my $hash = $minus->to_hash();
    is($hash->{op}, 'MinusF', 'op is MinusF');
    is($hash->{id}, $minus->id, 'id matches');
    is(ref($hash->{inputs}), 'ARRAY', 'inputs is array');
    is(scalar(@{$hash->{inputs}}), 1, 'one input (unary)');
    is($hash->{attributes}{operand_id}, $operand->id, 'operand_id in attributes');
};

# ============================================================
# Peephole optimizations
# ============================================================

subtest 'MinusF peephole constant folding' => sub {
    my $minus = Chalk::IR::Node::MinusF->new(
        operand => Chalk::IR::Node::ConstantF->new(value => 2.5)
    );

    my $result = $minus->peephole();
    isa_ok($result, 'Chalk::IR::Node::ConstantF', 'constant folding produces ConstantF');
    is($result->value, -2.5, 'folded to constant -2.5');
};

subtest 'MinusF idealize double negation: -(-x) = x' => sub {
    my $x = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $inner_minus = Chalk::IR::Node::MinusF->new(operand => $x);
    my $outer_minus = Chalk::IR::Node::MinusF->new(operand => $inner_minus);

    # Test idealize() directly
    my $result = $outer_minus->idealize();
    ok($result, 'idealize returns a result for -(-x)');
    is($result->id, $x->id, '-(-x) = x (double negation elimination)');
};

subtest 'MinusF peephole integration: double negation' => sub {
    my $x = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $inner_minus = Chalk::IR::Node::MinusF->new(operand => $x);
    my $outer_minus = Chalk::IR::Node::MinusF->new(operand => $inner_minus);

    my $result = $outer_minus->peephole();
    is($result->id, $x->id, 'peephole: -(-x) = x');
};

done_testing();
