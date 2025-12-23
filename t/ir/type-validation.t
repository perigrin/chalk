#!/usr/bin/env perl
# ABOUTME: Test type validation pass for IR graphs
# ABOUTME: Ensures nodes have consistent types and compatible operands

use 5.42.0;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";
use Test2::V0;
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Graph;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::StrConcat;
use Chalk::IR::Node::Phi;
use Chalk::IR::Node::Region;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;
use Chalk::IR::Type::Union;
use Chalk::IR::TypePropagation;
use Chalk::IR::TypeValidator;

# Test: TypeValidator exists and has basic API
subtest 'TypeValidator basic infrastructure' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Simple arithmetic
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

    # Propagate types first
    my $propagation = Chalk::IR::TypePropagation->new(graph => $graph);
    my $type_map = $propagation->propagate();

    # Create validator
    my $validator = Chalk::IR::TypeValidator->new(
        graph => $graph,
        type_map => $type_map
    );

    ok(defined $validator, 'TypeValidator can be created');
    ok($validator->can('validate'), 'TypeValidator has validate() method');

    # Validate should return results
    my $result = $validator->validate();
    ok(defined $result, 'validate() returns a result');
};

# Test: Arithmetic operations with numeric operands are valid
subtest 'Valid arithmetic operations' => sub {
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

    my $propagation = Chalk::IR::TypePropagation->new(graph => $graph);
    my $type_map = $propagation->propagate();

    my $validator = Chalk::IR::TypeValidator->new(
        graph => $graph,
        type_map => $type_map
    );

    my $result = $validator->validate();
    ok($result->{valid}, 'Integer + Integer is valid');
    is(scalar(@{$result->{errors}}), 0, 'No validation errors');
};

# Test: Mixed int/float arithmetic is valid
subtest 'Valid mixed numeric types' => sub {
    my $graph = Chalk::IR::Graph->new();

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

    my $add = Chalk::IR::Node::Add->new(
        left => $int5,
        right => $float3
    );
    $graph->add_node($add);

    my $propagation = Chalk::IR::TypePropagation->new(graph => $graph);
    my $type_map = $propagation->propagate();

    my $validator = Chalk::IR::TypeValidator->new(
        graph => $graph,
        type_map => $type_map
    );

    my $result = $validator->validate();
    ok($result->{valid}, 'Integer + Float is valid (numeric promotion)');
    is(scalar(@{$result->{errors}}), 0, 'No validation errors');
};

# Test: Phi nodes with compatible types are valid
subtest 'Valid Phi nodes with compatible types' => sub {
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
    my $type_map = $propagation->propagate();

    my $validator = Chalk::IR::TypeValidator->new(
        graph => $graph,
        type_map => $type_map
    );

    my $result = $validator->validate();
    ok($result->{valid}, 'Phi(Int, Int) is valid');
    is(scalar(@{$result->{errors}}), 0, 'No validation errors');
};

# Test: Phi nodes with Union types are valid
subtest 'Valid Phi nodes with Union types' => sub {
    my $graph = Chalk::IR::Graph->new();

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

    my $region = Chalk::IR::Node::Region->new(inputs => []);
    $graph->add_node($region);

    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $region->id,
        inputs => [$region->id, $int5->id, $float3->id]
    );
    $graph->add_node($phi);

    my $propagation = Chalk::IR::TypePropagation->new(graph => $graph);
    my $type_map = $propagation->propagate();

    my $validator = Chalk::IR::TypeValidator->new(
        graph => $graph,
        type_map => $type_map
    );

    my $result = $validator->validate();
    ok($result->{valid}, 'Phi(Int, Float) creates Union and is valid');
    is(scalar(@{$result->{errors}}), 0, 'No validation errors');
};

# Test: Chained operations all have types
subtest 'Chained operations are validated' => sub {
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
    my $type_map = $propagation->propagate();

    my $validator = Chalk::IR::TypeValidator->new(
        graph => $graph,
        type_map => $type_map
    );

    my $result = $validator->validate();
    ok($result->{valid}, 'Chained arithmetic is valid');
    is(scalar(@{$result->{errors}}), 0, 'No validation errors');
};

# Test: String concatenation validation
subtest 'String operations validation' => sub {
    my $graph = Chalk::IR::Graph->new();

    # StrConcat nodes don't have compute_type yet, so they won't get types
    # This is expected to fail validation until StrConcat implements compute_type
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

    my $concat = Chalk::IR::Node::StrConcat->new(
        left => $const5,
        right => $const3
    );
    $graph->add_node($concat);

    my $propagation = Chalk::IR::TypePropagation->new(graph => $graph);
    my $type_map = $propagation->propagate();

    my $validator = Chalk::IR::TypeValidator->new(
        graph => $graph,
        type_map => $type_map
    );

    my $result = $validator->validate();
    # StrConcat doesn't have compute_type, so validation will report missing type
    ok(!$result->{valid}, 'String concat without type info is invalid');
    ok(scalar(@{$result->{errors}}) > 0, 'Validation reports missing type');
    like($result->{errors}[0], qr/StrConcat.*no type/i, 'Error mentions StrConcat missing type');
};

# Test: Validation reports nodes without types
subtest 'Missing types are detected' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $const5 = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5)
    );
    $graph->add_node($const5);

    # Create an empty type_map (simulating missing propagation)
    my $type_map = {};

    my $validator = Chalk::IR::TypeValidator->new(
        graph => $graph,
        type_map => $type_map
    );

    my $result = $validator->validate();
    ok(!$result->{valid}, 'Graph with missing types is invalid');
    ok(scalar(@{$result->{errors}}) > 0, 'Validation errors reported');

    # Check error contains node id
    my $error_text = join(' ', @{$result->{errors}});
    like($error_text, qr/node/i, 'Error mentions node');
};

# Integration test: Complex expression with multiple operations
subtest 'Integration: Complex arithmetic expression' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build: ((5 + 3) * 2) - 1
    # This tests type propagation through multiple levels

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

    my $const2 = Chalk::IR::Node::Constant->new(
        value => 2,
        type => Chalk::IR::Type::Integer->constant(2)
    );
    $graph->add_node($const2);

    # Need to load Multiply
    require Chalk::IR::Node::Multiply;
    my $mult = Chalk::IR::Node::Multiply->new(
        left => $add,
        right => $const2
    );
    $graph->add_node($mult);

    my $const1 = Chalk::IR::Node::Constant->new(
        value => 1,
        type => Chalk::IR::Type::Integer->constant(1)
    );
    $graph->add_node($const1);

    # Need to load Subtract
    require Chalk::IR::Node::Subtract;
    my $sub = Chalk::IR::Node::Subtract->new(
        left => $mult,
        right => $const1
    );
    $graph->add_node($sub);

    # Propagate and validate
    my $propagation = Chalk::IR::TypePropagation->new(graph => $graph);
    my $type_map = $propagation->propagate();

    my $validator = Chalk::IR::TypeValidator->new(
        graph => $graph,
        type_map => $type_map
    );

    my $result = $validator->validate();
    ok($result->{valid}, 'Complex arithmetic expression validates correctly');
    is(scalar(@{$result->{errors}}), 0, 'No validation errors in complex expression');

    # Verify all nodes have types
    for my $node ($const5, $const3, $add, $const2, $mult, $const1, $sub) {
        my $type = $type_map->{$node->id};
        ok(defined $type, sprintf('Node %d (%s) has type', $node->id, $node->op));
        ok($type->isa('Chalk::IR::Type::Integer'),
           sprintf('Node %d (%s) has Integer type', $node->id, $node->op));
    }
};

# Integration test: Control flow with Phi
subtest 'Integration: Control flow with Phi nodes' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Simulate: result = condition ? 10 : 20
    # This creates a Phi node merging two constants

    my $const10 = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->constant(10)
    );
    $graph->add_node($const10);

    my $const20 = Chalk::IR::Node::Constant->new(
        value => 20,
        type => Chalk::IR::Type::Integer->constant(20)
    );
    $graph->add_node($const20);

    my $region = Chalk::IR::Node::Region->new(inputs => []);
    $graph->add_node($region);

    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $region->id,
        inputs => [$region->id, $const10->id, $const20->id]
    );
    $graph->add_node($phi);

    # Use phi result in another operation
    my $const5 = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5)
    );
    $graph->add_node($const5);

    my $add = Chalk::IR::Node::Add->new(
        left => $phi,
        right => $const5
    );
    $graph->add_node($add);

    # Propagate and validate
    my $propagation = Chalk::IR::TypePropagation->new(graph => $graph);
    my $type_map = $propagation->propagate();

    my $validator = Chalk::IR::TypeValidator->new(
        graph => $graph,
        type_map => $type_map
    );

    my $result = $validator->validate();
    ok($result->{valid}, 'Control flow with Phi validates correctly');
    is(scalar(@{$result->{errors}}), 0, 'No validation errors with Phi');

    # Verify Phi result can be used in arithmetic
    my $phi_type = $type_map->{$phi->id};
    ok(defined $phi_type, 'Phi node has type');
    ok($phi_type->isa('Chalk::IR::Type::Integer'), 'Phi(Int, Int) = Integer');

    my $add_type = $type_map->{$add->id};
    ok(defined $add_type, 'Add after Phi has type');
    ok($add_type->isa('Chalk::IR::Type::Integer'), 'Add after Phi = Integer');
};
