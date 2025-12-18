#!/usr/bin/env perl
# ABOUTME: Test Phi node computes union of incoming types
# ABOUTME: Core to flow-sensitive typing at merge points

use 5.42.0;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";
use Test2::V0;
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Graph;
use Chalk::IR::Node::Phi;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Region;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;
use Chalk::IR::Type::Union;
use Chalk::IR::Type::Top;

# Create a graph to hold nodes
my $graph = Chalk::IR::Graph->new();

# Create constants of different types
my $int5 = Chalk::IR::Node::Constant->new(
    value => 5, type => Chalk::IR::Type::Integer->constant(5));
$graph->add_node($int5);

my $float3 = Chalk::IR::Node::Constant->new(
    value => 3.0, type => Chalk::IR::Type::Float->constant(3.0));
$graph->add_node($float3);

# Create a region for the Phi
my $region = Chalk::IR::Node::Region->new(
    inputs => [],
);
$graph->add_node($region);

# Test: Phi with same types returns that type
subtest 'Phi same types returns single type' => sub {
    my $int3 = Chalk::IR::Node::Constant->new(
        value => 3, type => Chalk::IR::Type::Integer->constant(3));
    $graph->add_node($int3);

    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $region->id,
        inputs => [$region->id, $int5->id, $int3->id],
    );
    $graph->add_node($phi);

    ok($phi->can('compute_type'), 'Phi has compute_type');
    my $type = $phi->compute_type($graph);
    ok($type->isa('Chalk::IR::Type::Integer'), 'Phi(Int, Int) = Integer');
};

# Test: Phi with different types returns union
subtest 'Phi different types returns union' => sub {
    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $region->id,
        inputs => [$region->id, $int5->id, $float3->id],
    );
    $graph->add_node($phi);

    my $type = $phi->compute_type($graph);
    ok($type->isa('Chalk::IR::Type::Union'), 'Phi(Int, Float) = Union');
    ok($type->contains(Chalk::IR::Type::Integer->TOP()), 'Union contains Int');
    ok($type->contains(Chalk::IR::Type::Float->TOP()), 'Union contains Float');
};

# Test: Phi with no inputs returns Top
subtest 'Phi with no inputs returns Top' => sub {
    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $region->id,
        inputs => [$region->id],
    );
    $graph->add_node($phi);

    my $type = $phi->compute_type($graph);
    ok($type->isa('Chalk::IR::Type::Top'), 'Phi() = Top');
};

# Test: Phi with single input returns that type
subtest 'Phi with single input returns that type' => sub {
    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $region->id,
        inputs => [$region->id, $int5->id],
    );
    $graph->add_node($phi);

    my $type = $phi->compute_type($graph);
    ok($type->isa('Chalk::IR::Type::Integer'), 'Phi(Int) = Integer');
};
