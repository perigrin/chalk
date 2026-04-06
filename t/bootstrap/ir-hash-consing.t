# ABOUTME: Tests for IR node hash consing - verifies deduplication works correctly
# ABOUTME: Ensures identical IR nodes share same reference through NodeFactory
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;

# Reset factory to ensure clean test state (prevents cross-test contamination)
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

# Test 1: Duplicate constants deduplicated
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $const1 = $factory->make('Constant',
        const_type => 'string',
        value => 'hello'
    );

    my $const2 = $factory->make('Constant',
        const_type => 'string',
        value => 'hello'
    );

    is($const1, $const2, 'identical constants return same reference');
    is(refaddr($const1), refaddr($const2), 'reference addresses match');
}

# Test 2: Different constants not deduplicated
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $const1 = $factory->make('Constant',
        const_type => 'string',
        value => 'hello'
    );

    my $const2 = $factory->make('Constant',
        const_type => 'string',
        value => 'world'
    );

    isnt($const1, $const2, 'different constants are different references');
    isnt(refaddr($const1), refaddr($const2), 'reference addresses differ');
}

# Test 3: Complex node deduplication
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    # Create shared input nodes
    my $var = $factory->make('Constant',
        const_type => 'string',
        value => '$x',
    );

    my $init = $factory->make('Constant',
        const_type => 'string',
        value => '42',
    );

    # Create two Constructor:VarDecl nodes with same inputs
    my $decl1 = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $var,
        initializer => $init,
    );

    my $decl2 = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $var,
        initializer => $init,
    );

    is($decl1, $decl2, 'complex nodes with same inputs deduplicated');
}

# Test 4: Hash key determinism - same data different code path
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    # Create inputs in one code path
    my $var1 = $factory->make('Constant',
        const_type => 'string',
        value => '$bar',
    );
    my $init1 = $factory->make('Constant',
        const_type => 'string',
        value => 'value1',
    );

    my $decl1 = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $var1,
        initializer => $init1,
    );

    # Create inputs in a different code path but same logical data
    my $var2 = $factory->make('Constant',
        const_type => 'string',
        value => '$bar',
    );
    my $init2 = $factory->make('Constant',
        const_type => 'string',
        value => 'value1',
    );

    my $decl2 = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $var2,
        initializer => $init2,
    );

    is($decl1, $decl2, 'hash key generation is deterministic');
}

# Test 5: Nested deduplication
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    # Build a small graph twice
    my $var1  = $factory->make('Constant', const_type => 'string', value => '$z');
    my $init1 = $factory->make('Constant', const_type => 'string', value => 'nested');
    my $decl1 = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $var1,
        initializer => $init1,
    );

    # Build same graph again
    my $var2  = $factory->make('Constant', const_type => 'string', value => '$z');
    my $init2 = $factory->make('Constant', const_type => 'string', value => 'nested');
    my $decl2 = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $var2,
        initializer => $init2,
    );

    is($var1,  $var2,  'leaf variable nodes deduplicated');
    is($init1, $init2, 'leaf init nodes deduplicated');
    is($decl1, $decl2, 'root VarDecl nodes deduplicated');
}

# Test 6: Factory singleton
{
    my $factory1 = Chalk::Bootstrap::IR::NodeFactory->instance;
    my $factory2 = Chalk::Bootstrap::IR::NodeFactory->instance;

    is($factory1, $factory2, 'factory returns same singleton instance');
    is(refaddr($factory1), refaddr($factory2), 'singleton reference addresses match');
}

# Test 7: node_count() returns 0 on fresh factory
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;
    is($factory->node_count(), 0, 'node_count() is 0 on fresh factory');
}

# Test 8: node_count() reflects number of created nodes
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    $factory->make('Constant', const_type => 'string', value => 'a');
    $factory->make('Constant', const_type => 'string', value => 'b');
    is($factory->node_count(), 2, 'node_count() reflects created nodes');

    # Duplicate doesn't increase count
    $factory->make('Constant', const_type => 'string', value => 'a');
    is($factory->node_count(), 2, 'node_count() unchanged after duplicate');
}

# Test 9: all_node_ids() returns sorted arrayref
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $node_b = $factory->make('Constant', const_type => 'string', value => 'b');
    my $node_a = $factory->make('Constant', const_type => 'string', value => 'a');

    my $ids = $factory->all_node_ids();
    is(ref($ids), 'ARRAY', 'all_node_ids() returns arrayref');
    is(scalar($ids->@*), 2, 'all_node_ids() has correct count');
    is($ids, [ sort($node_a->id(), $node_b->id()) ], 'all_node_ids() returns sorted IDs');
}

# Test 10: get_node() retrieves known node, returns undef for unknown
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $node = $factory->make('Constant', const_type => 'string', value => 'findme');
    my $retrieved = $factory->get_node($node->id());
    is($retrieved, $node, 'get_node() retrieves known node');
    is(refaddr($retrieved), refaddr($node), 'get_node() returns same reference');

    my $missing = $factory->get_node('nonexistent');
    ok(!defined($missing), 'get_node() returns undef for unknown ID');
}

# Test 11: remove_node() removes a node and decrements count
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $node = $factory->make('Constant', const_type => 'string', value => 'remove_me');
    is($factory->node_count(), 1, 'count is 1 before remove');

    $factory->remove_node($node->id());
    is($factory->node_count(), 0, 'count is 0 after remove');

    my $gone = $factory->get_node($node->id());
    ok(!defined($gone), 'get_node() returns undef after remove');
}

# Test 12: remove_node() on non-existent ID is a no-op
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    $factory->make('Constant', const_type => 'string', value => 'survivor');
    is($factory->node_count(), 1, 'count is 1 before removing missing ID');
    $factory->remove_node('nonexistent_id_12345');
    is($factory->node_count(), 1, 'count unchanged after removing non-existent ID');
}

# Test 13: remove_node() dies if node still has consumers
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $var  = $factory->make('Constant', const_type => 'string', value => '$consumer_test');
    my $init = $factory->make('Constant', const_type => 'string', value => 'init_val');
    my $decl = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $var,
        initializer => $init,
    );

    # $var has $decl as a consumer, so removing it should die
    eval { $factory->remove_node($var->id()) };
    like($@, qr/still has consumers/, 'remove_node() dies when node has consumers');

    # $decl has no consumers, so removing it should succeed
    eval { $factory->remove_node($decl->id()) };
    is($@, '', 'remove_node() succeeds when node has no consumers');
}

# Test 14: CFG nodes (If, Proj, Region, Loop, Phi) are NOT hash-consed
# CFG nodes represent control flow positions, not data values.
# Two different if-statements at different program points must be distinct
# even if they have the same control region and condition.
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    # Create shared inputs
    my $start = $factory->make('Start');
    my $region = $factory->make('Region', controls => [$start]);
    my $cond = $factory->make('Constant', const_type => 'string', value => 'test_cond');

    # Two If nodes with identical inputs should be DIFFERENT objects
    my $if1 = $factory->make('If', control => $region, condition => $cond);
    my $if2 = $factory->make('If', control => $region, condition => $cond);
    isnt(refaddr($if1), refaddr($if2),
        'CFG If nodes with same inputs are distinct objects');

    # Two Proj nodes with identical inputs should be DIFFERENT objects
    my $proj1 = $factory->make('Proj', source => $if1, index => 0);
    my $proj2 = $factory->make('Proj', source => $if1, index => 0);
    isnt(refaddr($proj1), refaddr($proj2),
        'CFG Proj nodes with same inputs are distinct objects');

    # Two Region nodes with identical inputs should be DIFFERENT objects
    my $region1 = $factory->make('Region', controls => [$proj1]);
    my $region2 = $factory->make('Region', controls => [$proj1]);
    isnt(refaddr($region1), refaddr($region2),
        'CFG Region nodes with same inputs are distinct objects');

    # Two Loop nodes with identical inputs should be DIFFERENT objects
    my $loop1 = $factory->make('Loop', entry_ctrl => $region, backedge_ctrl => undef);
    my $loop2 = $factory->make('Loop', entry_ctrl => $region, backedge_ctrl => undef);
    isnt(refaddr($loop1), refaddr($loop2),
        'CFG Loop nodes with same inputs are distinct objects');

    # Data nodes should still be hash-consed
    my $const1 = $factory->make('Constant', const_type => 'string', value => 'same');
    my $const2 = $factory->make('Constant', const_type => 'string', value => 'same');
    is(refaddr($const1), refaddr($const2),
        'data Constant nodes are still hash-consed');
}

done_testing;
