# ABOUTME: Test for use-def chains in Sea of Nodes IR
# ABOUTME: Validates that nodes track which other nodes use their output (use-def chains)

use lib 'lib';
use v5.42;
use lib 'lib';
use Test::More;
use lib 'lib';
use Test::Deep;

use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');

# Test that nodes can track their uses
subtest 'Node tracks uses via Graph' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create Constant node that depends on Start
    my $constant = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => ['node_0'],  # Uses Start
        attributes => { value => 42, type => 'Int' }
    );
    $graph->add_node($constant);

    # Create Return node that depends on both Start and Constant
    my $return = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Return',
        inputs => ['node_0', 'node_1'],  # Uses Start and Constant
        attributes => {}
    );
    $graph->add_node($return);

    # Test: Get uses of Start node (should be used by Constant and Return)
    my $start_uses = $graph->get_uses('node_0');
    ok($start_uses, 'get_uses returns a value for Start node');
    is(ref($start_uses), 'ARRAY', 'get_uses returns an array ref');
    cmp_bag($start_uses, ['node_1', 'node_2'],
            'Start node is used by Constant and Return');

    # Test: Get uses of Constant node (should be used by Return)
    my $const_uses = $graph->get_uses('node_1');
    ok($const_uses, 'get_uses returns a value for Constant node');
    is(ref($const_uses), 'ARRAY', 'get_uses returns an array ref');
    cmp_deeply($const_uses, ['node_2'],
               'Constant node is used by Return');

    # Test: Get uses of Return node (should have no uses)
    my $return_uses = $graph->get_uses('node_2');
    ok(defined($return_uses), 'get_uses returns a value for Return node');
    is(ref($return_uses), 'ARRAY', 'get_uses returns an array ref');
    cmp_deeply($return_uses, [],
               'Return node has no uses');
};

# Test that use-def chains are updated when nodes are added
subtest 'Use-def chains update when adding nodes' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Add Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Initially, Start has no uses
    my $uses = $graph->get_uses('node_0');
    cmp_deeply($uses, [], 'Start initially has no uses');

    # Add Constant node that uses Start
    my $constant = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 42, type => 'Int' }
    );
    $graph->add_node($constant);

    # Now Start should have one use
    $uses = $graph->get_uses('node_0');
    cmp_deeply($uses, ['node_1'],
               'Start has one use after adding Constant');

    # Add Return node that uses both Start and Constant
    my $return = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Return',
        inputs => ['node_0', 'node_1'],
        attributes => {}
    );
    $graph->add_node($return);

    # Now Start should have two uses, Constant should have one
    $uses = $graph->get_uses('node_0');
    cmp_bag($uses, ['node_1', 'node_2'],
            'Start has two uses after adding Return');

    $uses = $graph->get_uses('node_1');
    cmp_deeply($uses, ['node_2'],
               'Constant has one use after adding Return');
};

# Test use-def chains with more complex graph (Add operation)
subtest 'Use-def chains with arithmetic operations' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create nodes for: a = 10; b = 20; c = a + b;
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    my $const_a = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 10, type => 'Int' }
    );
    $graph->add_node($const_a);

    my $const_b = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 20, type => 'Int' }
    );
    $graph->add_node($const_b);

    my $add = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Add',
        inputs => ['node_1', 'node_2'],  # Uses both constants
        attributes => {
            left => { op => 'Constant', value => 10, type => 'Int' },
            right => { op => 'Constant', value => 20, type => 'Int' }
        }
    );
    $graph->add_node($add);

    # Verify use-def chains
    my $uses_a = $graph->get_uses('node_1');
    cmp_deeply($uses_a, ['node_3'],
               'Constant A is used by Add');

    my $uses_b = $graph->get_uses('node_2');
    cmp_deeply($uses_b, ['node_3'],
               'Constant B is used by Add');

    my $uses_add = $graph->get_uses('node_3');
    cmp_deeply($uses_add, [],
               'Add operation has no uses yet');
};

# Test that use-def chains handle Phi nodes correctly
subtest 'Use-def chains with Phi nodes' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create a Region node (merge point)
    my $region = Chalk::IR::Node->new(
        id => 'region_1',
        op => 'Region',
        inputs => ['ctrl_0', 'ctrl_1'],
        attributes => {}
    );
    $graph->add_node($region);

    # Create two value nodes
    my $val_0 = Chalk::IR::Node->new(
        id => 'val_0',
        op => 'Constant',
        inputs => [],
        attributes => { value => 10, type => 'Int' }
    );
    $graph->add_node($val_0);

    my $val_1 = Chalk::IR::Node->new(
        id => 'val_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 20, type => 'Int' }
    );
    $graph->add_node($val_1);

    # Create Phi node that uses Region and both values
    my $phi = Chalk::IR::Node->new(
        id => 'phi_1',
        op => 'Phi',
        inputs => ['region_1', 'val_0', 'val_1'],  # Region + alternatives
        attributes => {
            region_id => 'region_1'
        }
    );
    $graph->add_node($phi);

    # Verify use-def chains
    my $region_uses = $graph->get_uses('region_1');
    cmp_deeply($region_uses, ['phi_1'],
               'Region is used by Phi');

    my $val_0_uses = $graph->get_uses('val_0');
    cmp_deeply($val_0_uses, ['phi_1'],
               'First value is used by Phi');

    my $val_1_uses = $graph->get_uses('val_1');
    cmp_deeply($val_1_uses, ['phi_1'],
               'Second value is used by Phi');
};

done_testing();
