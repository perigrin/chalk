# ABOUTME: Test for OptimizerPipeline that composes multiple optimization passes
# ABOUTME: Validates pipeline construction, pass composition, and correct ordering of optimizations

use lib 'lib';
use v5.42;
use lib 'lib';
use Test::More;
use lib 'lib';
use Test::Deep;

# Load required modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Optimizer::GVN');
use_ok('Chalk::IR::OptimizerPipeline');

# Test 1: Empty pipeline passes graph through unchanged
subtest 'Empty pipeline' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build simple graph
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    my $const = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 42, type => 'Int' }
    );
    $graph->add_node($const);

    # Create empty pipeline
    my $pipeline = Chalk::IR::OptimizerPipeline->new(optimizers => []);

    # Materialize pending nodes before pipeline
    $graph->materialize_pending_nodes();

    # Apply pipeline
    my $result = $pipeline->apply($graph);

    # Should return graph unchanged
    is($result->node_count, 2, 'Empty pipeline preserves graph');
};

# Test 2: Single optimizer in pipeline
subtest 'Single optimizer pipeline' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build graph with redundant computation: (x+y) + (x+y)
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    my $const_x = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 3, type => 'Int' }
    );
    $graph->add_node($const_x);

    my $const_y = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => [],
        attributes => { value => 5, type => 'Int' }
    );
    $graph->add_node($const_y);

    # First Add: x + y
    my $add1 = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Add',
        inputs => ['node_1', 'node_2'],
        attributes => {}
    );
    $graph->add_node($add1);

    # Second Add: x + y (duplicate)
    my $add2 = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Add',
        inputs => ['node_1', 'node_2'],
        attributes => {}
    );
    $graph->add_node($add2);

    # Third Add: (x+y) + (x+y)
    my $add3 = Chalk::IR::Node->new(
        id => 'node_5',
        op => 'Add',
        inputs => ['node_3', 'node_4'],
        attributes => {}
    );
    $graph->add_node($add3);

    # Materialize pending nodes before counting/pipeline
    $graph->materialize_pending_nodes();

    # Before optimization: 6 nodes
    is($graph->node_count, 6, 'Graph has 6 nodes before optimization');

    # Create pipeline with GVN optimizer
    my $gvn = Chalk::IR::Optimizer::GVN->new();
    my $pipeline = Chalk::IR::OptimizerPipeline->new(optimizers => [$gvn]);

    # Apply pipeline
    my $result = $pipeline->apply($graph);

    # After GVN: Should eliminate one Add node
    ok($result->node_count < 6, 'Pipeline with GVN eliminates redundant nodes');
};

# Test 3: Multiple optimizers in sequence
subtest 'Multiple optimizer pipeline' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build graph
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    my $const = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 10, type => 'Int' }
    );
    $graph->add_node($const);

    # Materialize pending nodes before pipeline
    $graph->materialize_pending_nodes();

    # Create pipeline with multiple optimizers (GVN twice for testing)
    my $gvn1 = Chalk::IR::Optimizer::GVN->new();
    my $gvn2 = Chalk::IR::Optimizer::GVN->new();
    my $pipeline = Chalk::IR::OptimizerPipeline->new(optimizers => [$gvn1, $gvn2]);

    # Apply pipeline
    my $result = $pipeline->apply($graph);

    # Should still have 2 nodes
    is($result->node_count, 2, 'Multiple optimizers compose correctly');
};

# Test 4: Pipeline preserves graph entry point
subtest 'Pipeline preserves entry point' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);
    $graph->set_entry('node_0');

    # Materialize pending nodes before pipeline
    $graph->materialize_pending_nodes();

    my $pipeline = Chalk::IR::OptimizerPipeline->new(optimizers => []);
    my $result = $pipeline->apply($graph);

    is($result->entry, 'node_0', 'Pipeline preserves entry point');
};

# Test 5: Pipeline can be constructed with new() syntax
subtest 'Pipeline construction' => sub {
    my $gvn = Chalk::IR::Optimizer::GVN->new();

    # Test construction with array ref
    my $pipeline = Chalk::IR::OptimizerPipeline->new(optimizers => [$gvn]);
    ok(defined($pipeline), 'Pipeline can be constructed');

    # Test with empty array
    my $empty = Chalk::IR::OptimizerPipeline->new(optimizers => []);
    ok(defined($empty), 'Empty pipeline can be constructed');
};

done_testing();
