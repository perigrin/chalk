#!/usr/bin/env perl
# ABOUTME: Test ToFloat IR node - integer/boolean to float type conversion
# ABOUTME: Validates type widening and constant folding for int→float and bool→float conversion

use lib 'lib';
use 5.42.0;
use Test2::V0;

use Chalk::IR::Node::ToFloat;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;
use Chalk::IR::Type::Bool;

subtest 'ToFloat: basic node creation' => sub {
    my $int_const = Chalk::IR::Node::Constant->new(
        type  => Chalk::IR::Type::Integer->constant(42),
        value => 42,
    );
    my $tofloat = Chalk::IR::Node::ToFloat->new(operand => $int_const);

    ok $tofloat, 'Created ToFloat node';
    is $tofloat->op, 'ToFloat', 'Op is ToFloat';
    is $tofloat->operand, $int_const, 'Operand is correct';
};

subtest 'ToFloat: constant folding' => sub {
    my $int_const = Chalk::IR::Node::Constant->new(
        type  => Chalk::IR::Type::Integer->constant(42),
        value => 42,
    );
    my $tofloat = Chalk::IR::Node::ToFloat->new(operand => $int_const);

    # Peephole should fold constant int to constant float
    my $optimized = $tofloat->peephole();
    ok $optimized->isa('Chalk::IR::Node::Constant'),
        'Constant int converts to Constant with Float type';
    is $optimized->value, 42.0, 'Value is 42.0';
};

subtest 'ToFloat: type computation for constant' => sub {
    my $int_const = Chalk::IR::Node::Constant->new(
        type  => Chalk::IR::Type::Integer->constant(5),
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
        type  => Chalk::IR::Type::Integer->TOP(),
        value => undef,  # Non-constant
    );
    my $tofloat = Chalk::IR::Node::ToFloat->new(operand => $int_top);

    my $type = $tofloat->compute();
    ok $type->isa('Chalk::IR::Type::Float'), 'Result type is Float';
    # Should be Float TOP (unknown float)
};

subtest 'ToFloat: execution' => sub {
    my $int_const = Chalk::IR::Node::Constant->new(
        type  => Chalk::IR::Type::Integer->constant(7),
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
        type  => Chalk::IR::Type::Integer->constant(10),
        value => 10,
    );
    my $tofloat = Chalk::IR::Node::ToFloat->new(operand => $int_const);

    my $hash = $tofloat->to_hash();
    is $hash->{op}, 'ToFloat', 'Serialized op is ToFloat';
    is $hash->{attributes}{operand_id}, $int_const->id, 'Operand ID serialized';
    is scalar(@{$hash->{inputs}}), 1, 'One input';
    is $hash->{inputs}[0], $int_const->id, 'Input is operand ID';
};

# Boolean → Float conversion tests (Issue #333)
subtest 'ToFloat: boolean true to float' => sub {
    my $bool_true = Chalk::IR::Node::Constant->new(
        type  => Chalk::IR::Type::Bool->constant(1),
        value => 1,
    );
    my $tofloat = Chalk::IR::Node::ToFloat->new(operand => $bool_true);

    # Peephole should fold constant boolean to constant float
    my $optimized = $tofloat->peephole();
    ok $optimized->isa('Chalk::IR::Node::Constant'),
        'Constant boolean converts to Constant with Float type';
    is $optimized->value, 1.0, 'true converts to 1.0';
};

subtest 'ToFloat: boolean false to float' => sub {
    my $bool_false = Chalk::IR::Node::Constant->new(
        type  => Chalk::IR::Type::Bool->constant(0),
        value => 0,
    );
    my $tofloat = Chalk::IR::Node::ToFloat->new(operand => $bool_false);

    # Peephole should fold constant boolean to constant float
    my $optimized = $tofloat->peephole();
    ok $optimized->isa('Chalk::IR::Node::Constant'),
        'Constant boolean converts to Constant with Float type';
    is $optimized->value, 0.0, 'false converts to 0.0';
};

subtest 'ToFloat: type computation for boolean constant true' => sub {
    my $bool_true = Chalk::IR::Node::Constant->new(
        type  => Chalk::IR::Type::Bool->constant(1),
        value => 1,
    );
    my $tofloat = Chalk::IR::Node::ToFloat->new(operand => $bool_true);

    my $type = $tofloat->compute();
    ok $type->isa('Chalk::IR::Type::Float'), 'Result type is Float';
    ok $type->is_constant, 'Type is constant';
    is $type->value, 1.0, 'Constant value is 1.0';
};

subtest 'ToFloat: type computation for boolean constant false' => sub {
    my $bool_false = Chalk::IR::Node::Constant->new(
        type  => Chalk::IR::Type::Bool->constant(0),
        value => 0,
    );
    my $tofloat = Chalk::IR::Node::ToFloat->new(operand => $bool_false);

    my $type = $tofloat->compute();
    ok $type->isa('Chalk::IR::Type::Float'), 'Result type is Float';
    ok $type->is_constant, 'Type is constant';
    is $type->value, 0.0, 'Constant value is 0.0';
};

done_testing();
