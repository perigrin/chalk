#!/usr/bin/env perl
# ABOUTME: Tests for issue #229 - Graph.pm simplification
# ABOUTME: Verifies that add_node directly adds to graph and builds use-def chains immediately
use lib 'lib';
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Test::More;

use Chalk::IR::Graph;
use Chalk::IR::Node;

# Test 1: Basic add_node immediately adds to graph
subtest 'add_node immediately adds to graph' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $node = Chalk::IR::Node->new(
        id => 'test-node-1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 42 }
    );

    $graph->add_node($node);

    # After add_node, node should be immediately available
    is($graph->node_count, 1, 'Graph has 1 node immediately after add_node');
    ok($graph->get_node('test-node-1'), 'Node is immediately retrievable by ID');
    is($graph->get_node('test-node-1')->op, 'Constant', 'Retrieved node has correct op');
};

# Test 2: Use-def chains built immediately on add_node
subtest 'use-def chains built immediately' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create a constant node
    my $const = Chalk::IR::Node->new(
        id => 'const-1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 10 }
    );

    # Create a node that uses the constant
    my $add = Chalk::IR::Node->new(
        id => 'add-1',
        op => 'Add',
        inputs => ['const-1', 'const-1'],
        attributes => {}
    );

    $graph->add_node($const);
    $graph->add_node($add);

    # Verify use-def chains are immediately available
    my $uses = $graph->get_uses('const-1');
    is(ref($uses), 'ARRAY', 'get_uses returns array ref');
    is(scalar(@$uses), 2, 'const-1 has 2 uses (used twice by add-1)');
    is($uses->[0], 'add-1', 'First user is add-1');
    is($uses->[1], 'add-1', 'Second user is also add-1');
};

# Test 3: Entry point set on first node
subtest 'first node becomes entry point' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $node1 = Chalk::IR::Node->new(
        id => 'first-node',
        op => 'Start',
        inputs => [],
        attributes => {}
    );

    my $node2 = Chalk::IR::Node->new(
        id => 'second-node',
        op => 'Constant',
        inputs => [],
        attributes => { value => 1 }
    );

    $graph->add_node($node1);
    is($graph->entry, 'first-node', 'Entry set to first node');

    $graph->add_node($node2);
    is($graph->entry, 'first-node', 'Entry remains first node after adding more');
};

# Test 4: Use-def chains handle forward references (input nodes added later)
subtest 'use-def handles forward references' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Add a node that references an input that doesn't exist yet
    my $return = Chalk::IR::Node->new(
        id => 'return-1',
        op => 'Return',
        inputs => ['control-1', 'value-1'],  # Forward refs
        attributes => {}
    );

    $graph->add_node($return);

    # The use-def entry should exist even if the input node doesn't
    my $control_uses = $graph->get_uses('control-1');
    is(ref($control_uses), 'ARRAY', 'Use list created for forward reference');
    is(scalar(@$control_uses), 1, 'Forward ref has correct use count');
    is($control_uses->[0], 'return-1', 'Forward ref user is correct');

    # Now add the referenced node
    my $start = Chalk::IR::Node->new(
        id => 'control-1',
        op => 'Start',
        inputs => [],
        attributes => {}
    );

    $graph->add_node($start);

    # Verify the use chain is still correct
    $control_uses = $graph->get_uses('control-1');
    is(scalar(@$control_uses), 1, 'Use list preserved after adding referenced node');
};

# Test 5: Placeholder inputs are skipped
subtest 'placeholder inputs are skipped' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $node = Chalk::IR::Node->new(
        id => 'node-with-placeholder',
        op => 'Return',
        inputs => ['__CONTROL_PLACEHOLDER__', 'value-1'],
        attributes => {}
    );

    $graph->add_node($node);

    # Placeholder should not create use-def entry
    my $placeholder_uses = $graph->get_uses('__CONTROL_PLACEHOLDER__');
    is(scalar(@$placeholder_uses), 0, 'No uses registered for placeholder');

    # But real input should have use
    my $value_uses = $graph->get_uses('value-1');
    is(scalar(@$value_uses), 1, 'Real input has use registered');
};

# Test 6: Undefined inputs are skipped
subtest 'undefined inputs are skipped' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $node = Chalk::IR::Node->new(
        id => 'node-with-undef',
        op => 'Return',
        inputs => [undef, 'value-1'],
        attributes => {}
    );

    $graph->add_node($node);

    # Only the defined input should have use
    my $value_uses = $graph->get_uses('value-1');
    is(scalar(@$value_uses), 1, 'Defined input has use registered');
};

# Test 7: verify dead code methods removed - get_pending_node should not exist
subtest 'pending methods removed' => sub {
    my $graph = Chalk::IR::Graph->new();

    # These methods should no longer exist after the simplification
    ok(!$graph->can('get_pending_node'), 'get_pending_node method removed');
    ok(!$graph->can('get_pending_all'), 'get_pending_all method removed');
    ok(!$graph->can('clear_pending'), 'clear_pending method removed');
    ok(!$graph->can('materialize_pending_nodes'), 'materialize_pending_nodes method removed');
};

# Test 8: remove_node still works correctly
subtest 'remove_node works correctly' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $const = Chalk::IR::Node->new(
        id => 'const-to-remove',
        op => 'Constant',
        inputs => [],
        attributes => { value => 42 }
    );

    my $add = Chalk::IR::Node->new(
        id => 'add-node',
        op => 'Add',
        inputs => ['const-to-remove', 'const-to-remove'],
        attributes => {}
    );

    $graph->add_node($const);
    $graph->add_node($add);

    is($graph->node_count, 2, 'Graph has 2 nodes');

    # Remove the add node
    $graph->remove_node('add-node');

    is($graph->node_count, 1, 'Graph has 1 node after removal');
    ok(!$graph->get_node('add-node'), 'Removed node is gone');

    # Use-def chains should be updated
    my $uses = $graph->get_uses('const-to-remove');
    is(scalar(@$uses), 0, 'No uses remaining after removal');
};

done_testing();
