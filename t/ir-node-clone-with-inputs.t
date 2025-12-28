#!/usr/bin/env perl
# ABOUTME: Tests for clone_with_inputs across all IR node types
# ABOUTME: Issue #477 - Normalize IR node class inheritance hierarchy

use 5.42.0;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Test2::V0;
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Node;
use Chalk::IR::Node::Base;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Phi;
use Chalk::IR::Node::Region;
use Chalk::IR::Node::Start;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Ctrl;

subtest 'All polymorphic nodes should have clone_with_inputs' => sub {
    # Test that all polymorphic node classes have clone_with_inputs method

    my @polymorphic_classes = qw(
        Chalk::IR::Node::Constant
        Chalk::IR::Node::Add
        Chalk::IR::Node::Phi
        Chalk::IR::Node::Region
        Chalk::IR::Node::Start
    );

    for my $class (@polymorphic_classes) {
        ok $class->can('clone_with_inputs'),
            "$class has clone_with_inputs method";
    }
};

subtest 'clone_with_inputs preserves polymorphic type for Phi' => sub {
    # Create a simple Phi node
    my $const1 = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    my $const2 = Chalk::IR::Node::Constant->new(
        value => 2,
        type  => Chalk::IR::Type::Integer->constant(2),
    );

    # Create a region control
    my $ctrl = Chalk::IR::Node::Constant->new(
        value => 'Ctrl',
        type  => Chalk::IR::Type::Ctrl->new(),
    );

    my $region = Chalk::IR::Node::Region->new(
        inputs => [$ctrl->id],
    );

    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $region->id,
        inputs    => [$region->id, $const1->id, $const2->id],
    );

    # Build a node_map for cloning
    my %node_map = (
        $region->id => $region,
        $const1->id => $const1,
        $const2->id => $const2,
    );

    # Clone the Phi node
    my $cloned = $phi->clone_with_inputs(
        [$region->id, $const1->id, $const2->id],
        \%node_map,
        { region_id => $region->id },
    );

    isa_ok $cloned, ['Chalk::IR::Node::Phi'],
        'Cloned node preserves Phi type';
    is $cloned->op, 'Phi',
        'Cloned node has correct op';
    is $cloned->region_id, $region->id,
        'Cloned node has correct region_id';
};

subtest 'clone_with_inputs preserves polymorphic type for Region' => sub {
    # Create control inputs
    my $ctrl1 = Chalk::IR::Node::Constant->new(
        value => 'Ctrl',
        type  => Chalk::IR::Type::Ctrl->new(),
    );
    my $ctrl2 = Chalk::IR::Node::Constant->new(
        value => 'Ctrl',
        type  => Chalk::IR::Type::Ctrl->new(),
    );

    my $region = Chalk::IR::Node::Region->new(
        inputs => [$ctrl1->id, $ctrl2->id],
    );

    # Build a node_map for cloning
    my %node_map = (
        $ctrl1->id => $ctrl1,
        $ctrl2->id => $ctrl2,
    );

    # Clone the Region node
    my $cloned = $region->clone_with_inputs(
        [$ctrl1->id, $ctrl2->id],
        \%node_map,
        {},
    );

    isa_ok $cloned, ['Chalk::IR::Node::Region'],
        'Cloned node preserves Region type';
    is $cloned->op, 'Region',
        'Cloned node has correct op';
};

subtest 'clone_with_inputs works for Constant (leaf node)' => sub {
    my $const = Chalk::IR::Node::Constant->new(
        value => 42,
        type  => Chalk::IR::Type::Integer->constant(42),
    );

    my $cloned = $const->clone_with_inputs([], {}, {});

    isa_ok $cloned, ['Chalk::IR::Node::Constant'],
        'Cloned node preserves Constant type';
    is $cloned->value, 42,
        'Cloned node has correct value';
};

subtest 'clone_with_inputs works for Add (binary op)' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 2,
        type  => Chalk::IR::Type::Integer->constant(2),
    );

    my $add = Chalk::IR::Node::Add->new(
        left  => $left,
        right => $right,
    );

    my %node_map = (
        $left->id  => $left,
        $right->id => $right,
    );

    my $cloned = $add->clone_with_inputs(
        [$left->id, $right->id],
        \%node_map,
        {},
    );

    isa_ok $cloned, ['Chalk::IR::Node::Add'],
        'Cloned node preserves Add type';
    is $cloned->op, 'Add',
        'Cloned node has correct op';
};

subtest 'Node::Base subclasses can be cloned' => sub {
    # This is the key test - Base didn't have clone_with_inputs
    # which caused GVN to fall back to generic Node

    my $ctrl = Chalk::IR::Node::Constant->new(
        value => 'Ctrl',
        type  => Chalk::IR::Type::Ctrl->new(),
    );

    my $region = Chalk::IR::Node::Region->new(
        inputs => [$ctrl->id],
    );

    # Before fix: Base doesn't have clone_with_inputs
    # After fix: Base should have clone_with_inputs
    ok $region->can('clone_with_inputs'),
        'Region (inherits from Base) has clone_with_inputs';

    my %node_map = ($ctrl->id => $ctrl);
    my $cloned = $region->clone_with_inputs(
        [$ctrl->id],
        \%node_map,
        {},
    );

    # Critical: the cloned node should still be a Region, not generic Node
    isa_ok $cloned, ['Chalk::IR::Node::Region'],
        'Cloned Region is still a Region, not generic Node';
    isnt ref($cloned), 'Chalk::IR::Node',
        'Cloned Region is not a generic Chalk::IR::Node';
};
