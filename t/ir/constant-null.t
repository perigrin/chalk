#!/usr/bin/env perl
# ABOUTME: Test null constant support in IR nodes
# ABOUTME: Validates that Constant nodes can represent null values with Maybe types

use lib 'lib';
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Class;
use Chalk::Grammar::Chalk::Type::Maybe;

subtest 'Constant: undef value with Maybe type' => sub {
    # Create a null constant for a Maybe[Class]
    my $null_constant = Chalk::IR::Node::Constant->new(
        value => undef,
        type  => Chalk::Grammar::Chalk::Type::Maybe->new(
            inner_type => Chalk::Grammar::Chalk::Type::Class->new(
                class_name => 'Point',
                fields => undef,  # Placeholder/forward ref
            ),
        ),
    );

    ok $null_constant, 'Created null constant';
    is $null_constant->value, undef, 'Constant value is undef';
    ok $null_constant->type isa Chalk::Grammar::Chalk::Type::Maybe, 'Type is Maybe';
    is $null_constant->execute(), undef, 'Execute returns undef';
};

subtest 'Constant: null distinguished from zero' => sub {
    # Null constant
    my $null = Chalk::IR::Node::Constant->new(
        value => undef,
        type  => Chalk::Grammar::Chalk::Type::Maybe->new(
            inner_type => Chalk::Grammar::Chalk::Type::Class->new(
                class_name => 'Node',
                fields => undef,
            ),
        ),
    );

    # Zero constant (different type)
    use Chalk::IR::Type::Integer;
    my $zero = Chalk::IR::Node::Constant->new(
        value => 0,
        type  => Chalk::IR::Type::Integer->new(),
    );

    isnt $null->id, $zero->id, 'Null and zero have different IDs';
    is $null->value, undef, 'Null value is undef';
    is $zero->value, 0, 'Zero value is 0';

    # Type check
    ok $null->type isa Chalk::Grammar::Chalk::Type::Maybe, 'Null has Maybe type';
    ok $zero->type isa Chalk::IR::Type::Integer, 'Zero has Integer type';
};

subtest 'Constant: null with complete class type' => sub {
    use Chalk::Grammar::Chalk::TypeRegistry;

    # Reset registry for clean test
    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    # Register a complete class
    my $point_class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Point',
        fields => {
            x => Chalk::IR::Type::Integer->new(),
            y => Chalk::IR::Type::Integer->new(),
        },
    );
    $registry->register('Point', $point_class);

    # Create null constant for this class
    my $null_point = Chalk::IR::Node::Constant->new(
        value => undef,
        type  => Chalk::Grammar::Chalk::Type::Maybe->new(
            inner_type => $point_class,
        ),
    );

    ok $null_point, 'Created null constant for complete class';
    is $null_point->value, undef, 'Value is undef';
    ok $null_point->type->inner_type->is_complete(), 'Inner class type is complete';
};
