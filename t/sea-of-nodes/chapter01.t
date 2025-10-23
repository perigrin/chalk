# ABOUTME: Test for Sea of Nodes IR generation - Chapter 1: Return constant
# ABOUTME: Validates that parsing 'return 42;' generates correct IR graph with Start, Constant, and Return nodes

use v5.42;
use Test::More;
use Test::Deep;

# Test that we can load the IR modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');

# Test manual IR graph construction for Chapter 1
# This tests the IR infrastructure before we integrate with the parser
subtest 'Manual IR graph construction for return 42' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create Start node (entry point)
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create Constant node (value 42)
    my $constant = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => ['node_0'],  # Non-semantic edge to Start for traversability
        attributes => { value => 42, type => 'Int' }
    );
    $graph->add_node($constant);

    # Create Return node (returns the constant)
    my $return = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Return',
        inputs => ['node_0', 'node_1'],  # Control from Start, data from Constant
        attributes => {}
    );
    $graph->add_node($return);

    # Verify graph structure
    is($graph->entry, 'node_0', 'Entry node is Start');
    is($graph->node_count, 3, 'Graph has 3 nodes');

    # Verify Start node
    my $start_node = $graph->get_node('node_0');
    ok($start_node, 'Start node exists');
    is($start_node->op, 'Start', 'Start node has correct op');
    is(scalar @{$start_node->inputs}, 0, 'Start node has no inputs');
    is($start_node->attributes->{function}, 'main', 'Start node has function name');

    # Verify Constant node
    my $const_node = $graph->get_node('node_1');
    ok($const_node, 'Constant node exists');
    is($const_node->op, 'Constant', 'Constant node has correct op');
    cmp_deeply($const_node->inputs, ['node_0'], 'Constant connects to Start');
    is($const_node->attributes->{value}, 42, 'Constant has value 42');
    is($const_node->attributes->{type}, 'Int', 'Constant has type Int');

    # Verify Return node
    my $ret_node = $graph->get_node('node_2');
    ok($ret_node, 'Return node exists');
    is($ret_node->op, 'Return', 'Return node has correct op');
    cmp_deeply($ret_node->inputs, ['node_0', 'node_1'],
               'Return connects to Start (control) and Constant (data)');
};

# Test IR Builder generates correct IR from code
subtest 'IR Builder generates correct IR for return 42' => sub {
    use_ok('Chalk::IR::Builder');

    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->build_from_code("return 42;");

    # Verify graph structure matches manual construction
    ok($graph, 'Builder returns a graph');
    is($graph->node_count, 3, 'Generated graph has 3 nodes');

    # Verify Start node
    my $start_node = $graph->get_node('node_0');
    ok($start_node, 'Start node exists');
    is($start_node->op, 'Start', 'Start node has correct op');
    is(scalar @{$start_node->inputs}, 0, 'Start node has no inputs');
    is($start_node->attributes->{function}, 'main', 'Start node has function name');

    # Verify Constant node
    my $const_node = $graph->get_node('node_1');
    ok($const_node, 'Constant node exists');
    is($const_node->op, 'Constant', 'Constant node has correct op');
    cmp_deeply($const_node->inputs, ['node_0'], 'Constant connects to Start');
    is($const_node->attributes->{value}, 42, 'Constant has value 42');
    is($const_node->attributes->{type}, 'Int', 'Constant has type Int');

    # Verify Return node
    my $ret_node = $graph->get_node('node_2');
    ok($ret_node, 'Return node exists');
    is($ret_node->op, 'Return', 'Return node has correct op');
    cmp_deeply($ret_node->inputs, ['node_0', 'node_1'],
               'Return connects to Start (control) and Constant (data)');
};

# Test JSON serialization
subtest 'JSON serialization' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    my $constant = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 42, type => 'Int' }
    );
    $graph->add_node($constant);

    my $return = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Return',
        inputs => ['node_0', 'node_1'],
        attributes => {}
    );
    $graph->add_node($return);

    # Convert to JSON
    my $json = $graph->to_json();
    ok($json, 'Graph can be serialized to JSON');

    # Verify JSON structure
    is($json->{version}, '1.0', 'JSON has version 1.0');
    is($json->{entry}, 'node_0', 'JSON has correct entry node');
    is(scalar @{$json->{nodes}}, 3, 'JSON has 3 nodes');

    # Find nodes in JSON by ID
    my %json_nodes = map { $_->{id} => $_ } @{$json->{nodes}};

    # Verify Start node in JSON
    ok(exists $json_nodes{'node_0'}, 'Start node in JSON');
    is($json_nodes{'node_0'}{op}, 'Start', 'Start node op in JSON');
    cmp_deeply($json_nodes{'node_0'}{inputs}, [], 'Start node inputs in JSON');

    # Verify Constant node in JSON
    ok(exists $json_nodes{'node_1'}, 'Constant node in JSON');
    is($json_nodes{'node_1'}{op}, 'Constant', 'Constant node op in JSON');
    is($json_nodes{'node_1'}{attributes}{value}, 42, 'Constant value in JSON');

    # Verify Return node in JSON
    ok(exists $json_nodes{'node_2'}, 'Return node in JSON');
    is($json_nodes{'node_2'}{op}, 'Return', 'Return node op in JSON');
    cmp_deeply($json_nodes{'node_2'}{inputs}, ['node_0', 'node_1'],
               'Return node inputs in JSON');
};

# Test JSON round-trip (to_json and from_json)
subtest 'JSON round-trip' => sub {
    my $graph1 = Chalk::IR::Graph->new();

    $graph1->add_node(Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    ));

    $graph1->add_node(Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 42, type => 'Int' }
    ));

    $graph1->add_node(Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Return',
        inputs => ['node_0', 'node_1'],
        attributes => {}
    ));

    # Serialize to JSON
    my $json = $graph1->to_json();

    # Deserialize back to Graph
    my $graph2 = Chalk::IR::Graph->from_json($json);

    # Verify reconstructed graph
    is($graph2->entry, 'node_0', 'Reconstructed graph has correct entry');
    is($graph2->node_count, 3, 'Reconstructed graph has 3 nodes');

    # Verify nodes are identical
    for my $id (qw(node_0 node_1 node_2)) {
        my $node1 = $graph1->get_node($id);
        my $node2 = $graph2->get_node($id);

        is($node2->id, $node1->id, "Node $id: ID matches");
        is($node2->op, $node1->op, "Node $id: op matches");
        cmp_deeply($node2->inputs, $node1->inputs, "Node $id: inputs match");
        cmp_deeply($node2->attributes, $node1->attributes, "Node $id: attributes match");
    }
};

done_testing();
