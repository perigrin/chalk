# ABOUTME: Test for Sea of Nodes IR generation - Array support (Issue #98 Phase 2)
# ABOUTME: Validates IR generation for array creation, indexing, push, and length operations

use v5.42;
use lib 'lib';
use Test::More;
use Test::Deep;

# Test that we can load the IR modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Builder');

# Test manual IR graph construction for array operations
# This tests the IR infrastructure for Phase 2: Array Support
subtest 'Manual IR graph construction for array operations' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create Start node (entry point)
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create ArrayNew node for: my @arr = ();
    my $array_new = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'ArrayNew',
        inputs => ['node_0'],  # Control dependency
        attributes => {}
    );
    $graph->add_node($array_new);

    # Create constants for array values
    my $const_5 = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 5, type => 'Int' }
    );
    $graph->add_node($const_5);

    my $const_10 = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 10, type => 'Int' }
    );
    $graph->add_node($const_10);

    # Create ArrayPush node for: push @arr, 5;
    my $array_push = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'ArrayPush',
        inputs => ['node_0', 'node_1', 'node_2'],  # Control, array, value
        attributes => {
            array => { op => 'NodeRef', node_id => 'node_1' },
            value => { op => 'NodeRef', node_id => 'node_2' }
        }
    );
    $graph->add_node($array_push);

    # Create constant for array index
    my $const_0 = Chalk::IR::Node->new(
        id => 'node_5',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 0, type => 'Int' }
    );
    $graph->add_node($const_0);

    # Create ArrayGet node for: $arr[0]
    my $array_get = Chalk::IR::Node->new(
        id => 'node_6',
        op => 'ArrayGet',
        inputs => ['node_0', 'node_4', 'node_5'],  # Control, array, index
        attributes => {
            array => { op => 'NodeRef', node_id => 'node_4' },
            index => { op => 'NodeRef', node_id => 'node_5' }
        }
    );
    $graph->add_node($array_get);

    # Create ArraySet node for: $arr[0] = 10;
    my $array_set = Chalk::IR::Node->new(
        id => 'node_7',
        op => 'ArraySet',
        inputs => ['node_0', 'node_4', 'node_5', 'node_3'],  # Control, array, index, value
        attributes => {
            array => { op => 'NodeRef', node_id => 'node_4' },
            index => { op => 'NodeRef', node_id => 'node_5' },
            value => { op => 'NodeRef', node_id => 'node_3' }
        }
    );
    $graph->add_node($array_set);

    # Create ArrayLength node for: scalar(@arr)
    my $array_length = Chalk::IR::Node->new(
        id => 'node_8',
        op => 'ArrayLength',
        inputs => ['node_0', 'node_7'],  # Control, array
        attributes => {
            array => { op => 'NodeRef', node_id => 'node_7' }
        }
    );
    $graph->add_node($array_length);

    # Create Return node (returns the array length)
    my $return = Chalk::IR::Node->new(
        id => 'node_9',
        op => 'Return',
        inputs => ['node_0', 'node_8'],  # Control, data
        attributes => {}
    );
    $graph->add_node($return);

    # Verify graph structure
    is($graph->entry, 'node_0', 'Entry node is Start');
    is($graph->node_count, 10, 'Graph has 10 nodes');

    # Verify ArrayNew node
    my $new_node = $graph->get_node('node_1');
    ok($new_node, 'ArrayNew node exists');
    is($new_node->op, 'ArrayNew', 'ArrayNew node has correct op');

    # Verify ArrayPush node
    my $push_node = $graph->get_node('node_4');
    ok($push_node, 'ArrayPush node exists');
    is($push_node->op, 'ArrayPush', 'ArrayPush node has correct op');
    is($push_node->attributes->{array}{node_id}, 'node_1', 'ArrayPush references correct array');
    is($push_node->attributes->{value}{node_id}, 'node_2', 'ArrayPush has correct value');

    # Verify ArrayGet node
    my $get_node = $graph->get_node('node_6');
    ok($get_node, 'ArrayGet node exists');
    is($get_node->op, 'ArrayGet', 'ArrayGet node has correct op');
    is($get_node->attributes->{array}{node_id}, 'node_4', 'ArrayGet references correct array');
    is($get_node->attributes->{index}{node_id}, 'node_5', 'ArrayGet has correct index');

    # Verify ArraySet node
    my $set_node = $graph->get_node('node_7');
    ok($set_node, 'ArraySet node exists');
    is($set_node->op, 'ArraySet', 'ArraySet node has correct op');
    is($set_node->attributes->{array}{node_id}, 'node_4', 'ArraySet references correct array');
    is($set_node->attributes->{index}{node_id}, 'node_5', 'ArraySet has correct index');
    is($set_node->attributes->{value}{node_id}, 'node_3', 'ArraySet has correct value');

    # Verify ArrayLength node
    my $length_node = $graph->get_node('node_8');
    ok($length_node, 'ArrayLength node exists');
    is($length_node->op, 'ArrayLength', 'ArrayLength node has correct op');
    is($length_node->attributes->{array}{node_id}, 'node_7', 'ArrayLength references correct array');
};

# Test IR Builder methods for array operations
subtest 'IR Builder methods for array support' => sub {
    use_ok('Chalk::IR::Builder');

    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->graph;

    # Build Start node
    my $start = $builder->build_start_node('main');
    is($start->op, 'Start', 'Builder creates Start node');

    # Build ArrayNew node
    my $array = $builder->build_array_new_node();
    ok($array, 'Builder creates ArrayNew node');
    is($array->op, 'ArrayNew', 'ArrayNew has correct op');

    # Build constants
    my $const_5 = $builder->build_constant_node(5);
    my $const_10 = $builder->build_constant_node(10);
    my $const_0 = $builder->build_constant_node(0);

    # Build ArrayPush node
    my $array_push = $builder->build_array_push_node($array, $const_5);
    ok($array_push, 'Builder creates ArrayPush node');
    is($array_push->op, 'ArrayPush', 'ArrayPush has correct op');

    # Build ArrayGet node
    my $array_get = $builder->build_array_get_node($array_push, $const_0);
    ok($array_get, 'Builder creates ArrayGet node');
    is($array_get->op, 'ArrayGet', 'ArrayGet has correct op');

    # Build ArraySet node
    my $array_set = $builder->build_array_set_node($array_push, $const_0, $const_10);
    ok($array_set, 'Builder creates ArraySet node');
    is($array_set->op, 'ArraySet', 'ArraySet has correct op');

    # Build ArrayLength node
    my $array_length = $builder->build_array_length_node($array_set);
    ok($array_length, 'Builder creates ArrayLength node');
    is($array_length->op, 'ArrayLength', 'ArrayLength has correct op');

    # Verify all nodes are in the graph
    ok($graph->get_node($array->id), 'ArrayNew in graph');
    ok($graph->get_node($array_push->id), 'ArrayPush in graph');
    ok($graph->get_node($array_get->id), 'ArrayGet in graph');
    ok($graph->get_node($array_set->id), 'ArraySet in graph');
    ok($graph->get_node($array_length->id), 'ArrayLength in graph');
};

done_testing();
