#!/usr/bin/env perl
# ABOUTME: Test ToFloat IR node - integer to float type conversion
# ABOUTME: Validates type widening and constant folding for int→float conversion

use lib 'lib';
use 5.42.0;
use Test2::V0;

use Chalk::IR::Node::ToFloat;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;

subtest 'ToFloat: basic node creation' => sub {
    my $int_const = Chalk::IR::Node::Constant->new(
        type  => 'Int',
        value => 42,
    );
    my $tofloat = Chalk::IR::Node::ToFloat->new(operand => $int_const);

    ok $tofloat, 'Created ToFloat node';
    is $tofloat->op, 'ToFloat', 'Op is ToFloat';
    is $tofloat->operand, $int_const, 'Operand is correct';
};

subtest 'ToFloat: constant folding' => sub {
    my $int_const = Chalk::IR::Node::Constant->new(
        type  => 'Int',
        value => 42,
    );
    my $tofloat = Chalk::IR::Node::ToFloat->new(operand => $int_const);

    # Peephole should fold constant int to constant float
    my $optimized = $tofloat->peephole();
    ok $optimized->isa('Chalk::IR::Node::ConstantF'),
        'Constant int converts to ConstantF';
    is $optimized->value, 42.0, 'Value is 42.0';
};

subtest 'ToFloat: type computation for constant' => sub {
    my $int_const = Chalk::IR::Node::Constant->new(
        type  => 'Int',
        value => 5,
    );
    my $tofloat = Chalk::IR::Node::ToFloat->new(operand => $int_const);

    my $type = $tofloat->compute();
    ok $type->isa('Chalk::IR::Type::Float'), 'Result type is Float';
    ok $type->is_constant, 'Type is constant';
    is $type->value, 5.0, 'Constant value is 5.0';
};

subtest 'ToFloat: type computation for non-constant' => sub {
    # Create a non-constant integer (TOP)
    my $int_top = Chalk::IR::Node::Constant->new(
        type  => 'Int',
        value => undef,  # Non-constant
    );
    my $tofloat = Chalk::IR::Node::ToFloat->new(operand => $int_top);

    my $type = $tofloat->compute();
    ok $type->isa('Chalk::IR::Type::Float'), 'Result type is Float';
    # Should be Float TOP (unknown float)
};

subtest 'ToFloat: execution' => sub {
    my $int_const = Chalk::IR::Node::Constant->new(
        type  => 'Int',
        value => 7,
    );
    my $tofloat = Chalk::IR::Node::ToFloat->new(operand => $int_const);

    # Create execution context
    my $ctx = sub {
        my $key = shift;
        if ($key eq "node:" . $int_const->id) {
            return 7;  # Integer value
        }
        die "Unknown context key: $key";
    };

    my $result = $tofloat->execute($ctx);
    is $result, 7.0, 'Execution converts 7 to 7.0';
};

subtest 'ToFloat: serialization' => sub {
    my $int_const = Chalk::IR::Node::Constant->new(
        type  => 'Int',
        value => 10,
    );
    my $tofloat = Chalk::IR::Node::ToFloat->new(operand => $int_const);

    my $hash = $tofloat->to_hash();
    is $hash->{op}, 'ToFloat', 'Serialized op is ToFloat';
    is $hash->{attributes}{operand_id}, $int_const->id, 'Operand ID serialized';
    is scalar(@{$hash->{inputs}}), 1, 'One input';
    is $hash->{inputs}[0], $int_const->id, 'Input is operand ID';
};

done_testing();
