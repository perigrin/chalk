# ABOUTME: Test for Sea of Nodes IR generation - Hash support (Issue #98 Phase 3)
# ABOUTME: Validates IR generation for hash creation, key access, assignment, keys, and exists operations

use v5.42;
use Test::More;
use Test::Deep;

# Test that we can load the IR modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Builder');

# Test manual IR graph construction for hash operations
# This tests the IR infrastructure for Phase 3: Hash Support
subtest 'Manual IR graph construction for hash operations' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create Start node (entry point)
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create HashNew node for: my %hash = ();
    my $hash_new = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'HashNew',
        inputs => ['node_0'],  # Control dependency
        attributes => {}
    );
    $graph->add_node($hash_new);

    # Create constant for hash key
    my $const_key = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 'name', type => 'Str' }
    );
    $graph->add_node($const_key);

    # Create constant for hash value
    my $const_value = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 'Chalk', type => 'Str' }
    );
    $graph->add_node($const_value);

    # Create HashSet node for: $hash{name} = 'Chalk';
    my $hash_set = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'HashSet',
        inputs => ['node_0', 'node_1', 'node_2', 'node_3'],  # Control, hash, key, value
        attributes => {
            hash => { op => 'NodeRef', node_id => 'node_1' },
            key => { op => 'NodeRef', node_id => 'node_2' },
            value => { op => 'NodeRef', node_id => 'node_3' }
        }
    );
    $graph->add_node($hash_set);

    # Create HashGet node for: $hash{name}
    my $hash_get = Chalk::IR::Node->new(
        id => 'node_5',
        op => 'HashGet',
        inputs => ['node_0', 'node_4', 'node_2'],  # Control, hash, key
        attributes => {
            hash => { op => 'NodeRef', node_id => 'node_4' },
            key => { op => 'NodeRef', node_id => 'node_2' }
        }
    );
    $graph->add_node($hash_get);

    # Create HashExists node for: exists $hash{name}
    my $hash_exists = Chalk::IR::Node->new(
        id => 'node_6',
        op => 'HashExists',
        inputs => ['node_0', 'node_4', 'node_2'],  # Control, hash, key
        attributes => {
            hash => { op => 'NodeRef', node_id => 'node_4' },
            key => { op => 'NodeRef', node_id => 'node_2' }
        }
    );
    $graph->add_node($hash_exists);

    # Create HashKeys node for: keys(%hash)
    my $hash_keys = Chalk::IR::Node->new(
        id => 'node_7',
        op => 'HashKeys',
        inputs => ['node_0', 'node_4'],  # Control, hash
        attributes => {
            hash => { op => 'NodeRef', node_id => 'node_4' }
        }
    );
    $graph->add_node($hash_keys);

    # Create Return node (returns the keys array)
    my $return = Chalk::IR::Node->new(
        id => 'node_8',
        op => 'Return',
        inputs => ['node_0', 'node_7'],  # Control, data
        attributes => {}
    );
    $graph->add_node($return);

    # Verify graph structure
    is($graph->entry, 'node_0', 'Entry node is Start');
    is($graph->node_count, 9, 'Graph has 9 nodes');

    # Verify HashNew node
    my $new_node = $graph->get_node('node_1');
    ok($new_node, 'HashNew node exists');
    is($new_node->op, 'HashNew', 'HashNew node has correct op');

    # Verify HashSet node
    my $set_node = $graph->get_node('node_4');
    ok($set_node, 'HashSet node exists');
    is($set_node->op, 'HashSet', 'HashSet node has correct op');
    is($set_node->attributes->{hash}{node_id}, 'node_1', 'HashSet references correct hash');
    is($set_node->attributes->{key}{node_id}, 'node_2', 'HashSet has correct key');
    is($set_node->attributes->{value}{node_id}, 'node_3', 'HashSet has correct value');

    # Verify HashGet node
    my $get_node = $graph->get_node('node_5');
    ok($get_node, 'HashGet node exists');
    is($get_node->op, 'HashGet', 'HashGet node has correct op');
    is($get_node->attributes->{hash}{node_id}, 'node_4', 'HashGet references correct hash');
    is($get_node->attributes->{key}{node_id}, 'node_2', 'HashGet has correct key');

    # Verify HashExists node
    my $exists_node = $graph->get_node('node_6');
    ok($exists_node, 'HashExists node exists');
    is($exists_node->op, 'HashExists', 'HashExists node has correct op');
    is($exists_node->attributes->{hash}{node_id}, 'node_4', 'HashExists references correct hash');
    is($exists_node->attributes->{key}{node_id}, 'node_2', 'HashExists has correct key');

    # Verify HashKeys node
    my $keys_node = $graph->get_node('node_7');
    ok($keys_node, 'HashKeys node exists');
    is($keys_node->op, 'HashKeys', 'HashKeys node has correct op');
    is($keys_node->attributes->{hash}{node_id}, 'node_4', 'HashKeys references correct hash');
};

# Test IR Builder methods for hash operations
subtest 'IR Builder methods for hash support' => sub {
    use_ok('Chalk::IR::Builder');

    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->graph;

    # Build Start node
    my $start = $builder->build_start_node('main');
    is($start->op, 'Start', 'Builder creates Start node');

    # Build HashNew node
    my $hash = $builder->build_hash_new_node();
    ok($hash, 'Builder creates HashNew node');
    is($hash->op, 'HashNew', 'HashNew has correct op');

    # Build constants for key and value
    my $const_key = $builder->build_constant_node('name');
    my $const_value = $builder->build_constant_node('Chalk');

    # Build HashSet node
    my $hash_set = $builder->build_hash_set_node($hash, $const_key, $const_value);
    ok($hash_set, 'Builder creates HashSet node');
    is($hash_set->op, 'HashSet', 'HashSet has correct op');

    # Build HashGet node
    my $hash_get = $builder->build_hash_get_node($hash_set, $const_key);
    ok($hash_get, 'Builder creates HashGet node');
    is($hash_get->op, 'HashGet', 'HashGet has correct op');

    # Build HashExists node
    my $hash_exists = $builder->build_hash_exists_node($hash_set, $const_key);
    ok($hash_exists, 'Builder creates HashExists node');
    is($hash_exists->op, 'HashExists', 'HashExists has correct op');

    # Build HashKeys node
    my $hash_keys = $builder->build_hash_keys_node($hash_set);
    ok($hash_keys, 'Builder creates HashKeys node');
    is($hash_keys->op, 'HashKeys', 'HashKeys has correct op');

    # Verify all nodes are in the graph
    ok($graph->get_node($hash->id), 'HashNew in graph');
    ok($graph->get_node($hash_set->id), 'HashSet in graph');
    ok($graph->get_node($hash_get->id), 'HashGet in graph');
    ok($graph->get_node($hash_exists->id), 'HashExists in graph');
    ok($graph->get_node($hash_keys->id), 'HashKeys in graph');
};

done_testing();
