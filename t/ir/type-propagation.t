#!/usr/bin/env perl
# ABOUTME: Test type propagation through IR data flow
# ABOUTME: Validates forward propagation and Phi node type merging

use 5.42.0;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";
use Test2::V0;
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Graph;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Phi;
use Chalk::IR::Node::Region;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;
use Chalk::IR::Type::Union;
use Chalk::IR::TypePropagation;

# Test: Type propagation through simple arithmetic
subtest 'Forward propagation through Add' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create: 5 + 3
    my $const5 = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5)
    );
    $graph->add_node($const5);

    my $const3 = Chalk::IR::Node::Constant->new(
        value => 3,
        type => Chalk::IR::Type::Integer->constant(3)
    );
    $graph->add_node($const3);

    my $add = Chalk::IR::Node::Add->new(
        left => $const5,
        right => $const3
    );
    $graph->add_node($add);

    # Create propagation pass
    my $propagation = Chalk::IR::TypePropagation->new(graph => $graph);

    # Propagate types
    $propagation->propagate();

    # Verify types were propagated
    my $const5_type = $propagation->get_type($const5->id);
    ok($const5_type->isa('Chalk::IR::Type::Integer'), 'Constant 5 has Integer type');

    my $const3_type = $propagation->get_type($const3->id);
    ok($const3_type->isa('Chalk::IR::Type::Integer'), 'Constant 3 has Integer type');

    my $add_type = $propagation->get_type($add->id);
    ok($add_type->isa('Chalk::IR::Type::Integer'), 'Add result has Integer type');
};

# Test: Phi nodes join types from multiple paths
subtest 'Phi node joins types correctly' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create constants of different types
    my $int5 = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5)
    );
    $graph->add_node($int5);

    my $float3 = Chalk::IR::Node::Constant->new(
        value => 3.0,
        type => Chalk::IR::Type::Float->constant(3.0)
    );
    $graph->add_node($float3);

    # Create a region for control flow merge
    my $region = Chalk::IR::Node::Region->new(inputs => []);
    $graph->add_node($region);

    # Create Phi node that merges int and float
    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $region->id,
        inputs => [$region->id, $int5->id, $float3->id]
    );
    $graph->add_node($phi);

    # Propagate types
    my $propagation = Chalk::IR::TypePropagation->new(graph => $graph);
    $propagation->propagate();

    # Phi should have union of Integer and Float
    my $phi_type = $propagation->get_type($phi->id);
    ok($phi_type->isa('Chalk::IR::Type::Union'), 'Phi creates union type');
    ok($phi_type->contains(Chalk::IR::Type::Integer->TOP()), 'Union contains Integer');
    ok($phi_type->contains(Chalk::IR::Type::Float->TOP()), 'Union contains Float');
};

# Test: Phi with same types meets them
subtest 'Phi with same types meets them' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $int5 = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5)
    );
    $graph->add_node($int5);

    my $int3 = Chalk::IR::Node::Constant->new(
        value => 3,
        type => Chalk::IR::Type::Integer->constant(3)
    );
    $graph->add_node($int3);

    my $region = Chalk::IR::Node::Region->new(inputs => []);
    $graph->add_node($region);

    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $region->id,
        inputs => [$region->id, $int5->id, $int3->id]
    );
    $graph->add_node($phi);

    my $propagation = Chalk::IR::TypePropagation->new(graph => $graph);
    $propagation->propagate();

    my $phi_type = $propagation->get_type($phi->id);
    ok($phi_type->isa('Chalk::IR::Type::Integer'), 'Phi(Int, Int) = Integer');
};

# Test: Chained operations propagate types
subtest 'Types propagate through operation chains' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build: (5 + 3) + 2
    my $const5 = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5)
    );
    $graph->add_node($const5);

    my $const3 = Chalk::IR::Node::Constant->new(
        value => 3,
        type => Chalk::IR::Type::Integer->constant(3)
    );
    $graph->add_node($const3);

    my $add1 = Chalk::IR::Node::Add->new(
        left => $const5,
        right => $const3
    );
    $graph->add_node($add1);

    my $const2 = Chalk::IR::Node::Constant->new(
        value => 2,
        type => Chalk::IR::Type::Integer->constant(2)
    );
    $graph->add_node($const2);

    my $add2 = Chalk::IR::Node::Add->new(
        left => $add1,
        right => $const2
    );
    $graph->add_node($add2);

    my $propagation = Chalk::IR::TypePropagation->new(graph => $graph);
    $propagation->propagate();

    my $add1_type = $propagation->get_type($add1->id);
    ok($add1_type->isa('Chalk::IR::Type::Integer'), 'First add is Integer');

    my $add2_type = $propagation->get_type($add2->id);
    ok($add2_type->isa('Chalk::IR::Type::Integer'), 'Second add is Integer');
};
