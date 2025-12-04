#!/usr/bin/env perl
# ABOUTME: Tests for ConstantF IR node (floating-point constants)
# ABOUTME: Verifies float constant node behavior, type computation, and execution

use 5.42.0;
use utf8;
use Test::More;
use experimental qw(class);

# Load required modules
use Chalk::IR::Node::ConstantF;
use Chalk::IR::Type::Float;

# ============================================================
# ConstantF node creation and basic properties
# ============================================================

subtest 'ConstantF node creation' => sub {
    my $pi = Chalk::IR::Node::ConstantF->new(value => 3.14159);
    my $e = Chalk::IR::Node::ConstantF->new(value => 2.71828);
    my $zero = Chalk::IR::Node::ConstantF->new(value => 0.0);
    my $neg = Chalk::IR::Node::ConstantF->new(value => -1.5);

    is($pi->value, 3.14159, 'pi value is 3.14159');
    is($e->value, 2.71828, 'e value is 2.71828');
    is($zero->value, 0.0, 'zero value is 0.0');
    is($neg->value, -1.5, 'negative value is -1.5');

    ok($pi->id, 'node has ID');
    is($pi->op, 'ConstantF', 'op is ConstantF');
};

# ============================================================
# Node properties
# ============================================================

subtest 'ConstantF node has no inputs' => sub {
    my $pi = Chalk::IR::Node::ConstantF->new(value => 3.14159);
    my $inputs = $pi->inputs();

    is(ref($inputs), 'ARRAY', 'inputs returns array ref');
    is(scalar(@$inputs), 0, 'ConstantF has no inputs (leaf node)');
};

# ============================================================
# Type computation
# ============================================================

subtest 'ConstantF compute() returns TypeFloat constant' => sub {
    my $pi = Chalk::IR::Node::ConstantF->new(value => 3.14159);
    my $type = $pi->compute();

    isa_ok($type, 'Chalk::IR::Type::Float', 'compute() returns TypeFloat');
    ok($type->is_constant(), 'type is constant');
    is($type->value, 3.14159, 'type has correct value');
};

subtest 'ConstantF with different values have different types' => sub {
    my $pi = Chalk::IR::Node::ConstantF->new(value => 3.14159);
    my $e = Chalk::IR::Node::ConstantF->new(value => 2.71828);

    my $pi_type = $pi->compute();
    my $e_type = $e->compute();

    ok($pi_type->is_constant(), 'pi type is constant');
    ok($e_type->is_constant(), 'e type is constant');
    isnt($pi_type->value, $e_type->value, 'types have different values');
};

# ============================================================
# Execution
# ============================================================

subtest 'ConstantF execute() returns the value' => sub {
    my $pi = Chalk::IR::Node::ConstantF->new(value => 3.14159);
    my $zero = Chalk::IR::Node::ConstantF->new(value => 0.0);
    my $neg = Chalk::IR::Node::ConstantF->new(value => -1.5);

    is($pi->execute(), 3.14159, 'execute() returns 3.14159');
    is($zero->execute(), 0.0, 'execute() returns 0.0');
    is($neg->execute(), -1.5, 'execute() returns -1.5');
};

# ============================================================
# Serialization
# ============================================================

subtest 'ConstantF to_hash() serialization' => sub {
    my $pi = Chalk::IR::Node::ConstantF->new(value => 3.14159);
    my $hash = $pi->to_hash();

    is($hash->{op}, 'ConstantF', 'op is ConstantF');
    is($hash->{id}, $pi->id, 'id matches');
    is(ref($hash->{inputs}), 'ARRAY', 'inputs is array');
    is(scalar(@{$hash->{inputs}}), 0, 'no inputs');
    is($hash->{attributes}{value}, 3.14159, 'value in attributes');
    isa_ok($hash->{attributes}{type}, 'Chalk::IR::Type::Float', 'type in attributes');
};

# ============================================================
# Peephole optimization
# ============================================================

subtest 'ConstantF peephole() returns self' => sub {
    my $pi = Chalk::IR::Node::ConstantF->new(value => 3.14159);
    my $result = $pi->peephole();

    is($result, $pi, 'peephole() returns self (constants are already optimal)');
};

done_testing();
