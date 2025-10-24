# ABOUTME: Test for memory aliasing analysis in Sea of Nodes IR
# ABOUTME: Ensures Load/Store operations handle potential aliasing correctly

use v5.42;
use Test::More;
use Test::Deep;

use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');

# Test that Store nodes track memory dependencies correctly
subtest 'Store nodes have may_alias flag' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create a Store node
    my $store = Chalk::IR::Node->new(
        id => 'store_1',
        op => 'Store',
        inputs => ['mem_0'],  # Previous memory state
        attributes => {
            location => 'x',
            value => { op => 'Constant', value => 42, type => 'Int' },
            may_alias => 1  # Conservative assumption: may alias with anything
        }
    );
    $graph->add_node($store);

    # Verify the store has the may_alias flag
    my $node = $graph->get_node('store_1');
    ok($node, 'Store node exists');
    is($node->op, 'Store', 'Node is a Store operation');
    ok(exists $node->attributes->{may_alias}, 'Store has may_alias attribute');
    is($node->attributes->{may_alias}, 1, 'may_alias is set to true (conservative)');
};

# Test that Load nodes check for potential aliasing with Stores
subtest 'Load nodes must not bypass potentially aliasing Stores' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create memory state chain: mem0 -> store1 -> store2 -> load
    # This represents: $x = 10; $y = 20; $z = $x;

    my $start = Chalk::IR::Node->new(
        id => 'start',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Initial memory state
    my $mem0 = Chalk::IR::Node->new(
        id => 'mem_0',
        op => 'Memory',
        inputs => ['start'],
        attributes => {}
    );
    $graph->add_node($mem0);

    # Store to location 'x': $x = 10
    my $store1 = Chalk::IR::Node->new(
        id => 'store_1',
        op => 'Store',
        inputs => ['mem_0'],
        attributes => {
            location => 'x',
            value => { op => 'Constant', value => 10, type => 'Int' },
            may_alias => 1
        }
    );
    $graph->add_node($store1);

    # Store to location 'y': $y = 20
    # This could potentially alias with 'x' (conservative assumption)
    my $store2 = Chalk::IR::Node->new(
        id => 'store_2',
        op => 'Store',
        inputs => ['store_1'],  # Depends on previous store
        attributes => {
            location => 'y',
            value => { op => 'Constant', value => 20, type => 'Int' },
            may_alias => 1
        }
    );
    $graph->add_node($store2);

    # Load from location 'x': read $x
    my $load = Chalk::IR::Node->new(
        id => 'load_1',
        op => 'Load',
        inputs => ['store_2'],  # Must depend on latest memory state
        attributes => {
            location => 'x',
            store_id => 'store_1',  # Original store for this location
            may_alias => 1
        }
    );
    $graph->add_node($load);

    # Verify the load has correct dependencies
    my $load_node = $graph->get_node('load_1');
    ok($load_node, 'Load node exists');
    is($load_node->op, 'Load', 'Node is a Load operation');

    # The load must depend on store_2 (latest memory state)
    # even though it's loading from location 'x' which was stored in store_1
    my $load_inputs = $load_node->inputs;
    is(scalar(@$load_inputs), 1, 'Load has one input');
    is($load_inputs->[0], 'store_2', 'Load depends on latest memory state (conservative aliasing)');

    ok(exists $load_node->attributes->{may_alias}, 'Load has may_alias attribute');
    is($load_node->attributes->{may_alias}, 1, 'Load may_alias is true (conservative)');
};

# Test that peephole optimization respects memory aliasing
subtest 'Peephole optimization must not incorrectly optimize through aliasing stores' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Problematic case: Store constant, then another store to different location,
    # then Load from first location. Without alias analysis, the Load optimization
    # in Node.pm lines 138-159 could incorrectly fold the Load to the constant
    # even though an intervening store might have modified the location.

    my $start = Chalk::IR::Node->new(
        id => 'start',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Store constant to location 'x': $x = 10
    my $store_x = Chalk::IR::Node->new(
        id => 'store_x',
        op => 'Store',
        inputs => ['start'],
        attributes => {
            location => 'x',
            value => { op => 'Constant', value => 10, type => 'Int' }
        }
    );
    $graph->add_node($store_x);

    # Store constant to location 'y': $y = 20
    # This could potentially alias with 'x' (e.g., if they're both array elements)
    my $store_y = Chalk::IR::Node->new(
        id => 'store_y',
        op => 'Store',
        inputs => ['store_x'],
        attributes => {
            location => 'y',
            value => { op => 'Constant', value => 20, type => 'Int' }
        }
    );
    $graph->add_node($store_y);

    # Load from location 'x': read $x
    # BUG: Current implementation in Node.pm:138-159 will constant-fold this to 10
    # because it sees store_id points to a Store with a constant value.
    # But this is incorrect if store_y might alias with store_x!
    my $load_x = Chalk::IR::Node->new(
        id => 'load_x',
        op => 'Load',
        inputs => ['store_y'],  # Latest memory state
        attributes => {
            location => 'x',
            store_id => 'store_x'  # Points to original store
        }
    );
    $graph->add_node($load_x);

    # Run peephole optimization
    my $optimized = $load_x->peephole($graph);

    # TEST: The current implementation INCORRECTLY optimizes this to a Constant.
    # With proper aliasing analysis, it should remain a Load because store_y
    # might have modified the same memory location.

    # This test will FAIL with current implementation, demonstrating the bug
    is($optimized->op, 'Load',
        'Load must not be constant-folded when intervening stores may alias');

    # Expected behavior: Load stays as Load operation
    # Current buggy behavior: Load gets optimized to Constant(10)
};

# Test that Graph validates memory operation ordering
subtest 'Graph enforces memory operation ordering with aliasing' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'start',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    my $mem0 = Chalk::IR::Node->new(
        id => 'mem_0',
        op => 'Memory',
        inputs => ['start'],
        attributes => {}
    );
    $graph->add_node($mem0);

    # Create a chain of stores: each store must depend on the previous one
    my $prev_mem = 'mem_0';
    for my $i (1..3) {
        my $store = Chalk::IR::Node->new(
            id => "store_$i",
            op => 'Store',
            inputs => [$prev_mem],
            attributes => {
                location => "var$i",
                value => { op => 'Constant', value => $i * 10, type => 'Int' },
                may_alias => 1  # Conservative: all stores may alias
            }
        );
        $graph->add_node($store);
        $prev_mem = "store_$i";
    }

    # Verify the chain is correctly formed
    my $store1 = $graph->get_node('store_1');
    my $store2 = $graph->get_node('store_2');
    my $store3 = $graph->get_node('store_3');

    is_deeply($store1->inputs, ['mem_0'], 'Store 1 depends on initial memory');
    is_deeply($store2->inputs, ['store_1'], 'Store 2 depends on Store 1');
    is_deeply($store3->inputs, ['store_2'], 'Store 3 depends on Store 2');

    # All stores should have may_alias flag
    ok($store1->attributes->{may_alias}, 'Store 1 has may_alias');
    ok($store2->attributes->{may_alias}, 'Store 2 has may_alias');
    ok($store3->attributes->{may_alias}, 'Store 3 has may_alias');
};

done_testing();
