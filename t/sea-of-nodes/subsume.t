# ABOUTME: Test for subsume() method on IR nodes for in-place replacement
# ABOUTME: Validates recursive clone-and-propagate pattern for immutable node replacement

use lib 'lib';
use 5.42.0;
use Test2::V0;
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Node;
use Chalk::IR::Graph;

subtest 'subsume basic: replacement node gets new uses' => sub {
    # Build: Start -> Constant(42) -> Return -> Stop
    # Replace Constant(42) with Constant(0)
    # Result: New Return' and Stop' nodes are created that use Constant(0)
    # Old Return and Stop remain but become orphaned (cleaned by DCE later)

    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_start',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' },
    );
    $graph->add_node($start);

    my $const42 = Chalk::IR::Node->new(
        id => 'node_const42',
        op => 'Constant',
        inputs => ['node_start'],
        attributes => { value => 42, type => 'Int' },
    );
    $graph->add_node($const42);

    my $return = Chalk::IR::Node->new(
        id => 'node_return',
        op => 'Return',
        inputs => ['node_start', 'node_const42'],
        attributes => {},
    );
    $graph->add_node($return);

    my $stop = Chalk::IR::Node->new(
        id => 'node_stop',
        op => 'Stop',
        inputs => ['node_return'],
        attributes => {},
    );
    $graph->add_node($stop);

    my $node_count_before = $graph->node_count();

    # Create replacement constant
    my $const0 = Chalk::IR::Node->new(
        id => 'node_const0',
        op => 'Constant',
        inputs => ['node_start'],
        attributes => { value => 0, type => 'Int' },
    );
    $graph->add_node($const0);

    # const0 initially has no uses
    my $const0_uses_before = $graph->get_uses('node_const0');
    is scalar($const0_uses_before->@*), 0, 'const0 has no uses before subsume';

    # Subsume: replace const42 with const0
    $const42->subsume($const0, $graph);

    # const0 should now have uses (the new cloned Return node)
    my $const0_uses_after = $graph->get_uses('node_const0');
    ok scalar($const0_uses_after->@*) > 0, 'const0 has uses after subsume';

    # Graph should have more nodes (cloned Return and Stop)
    ok $graph->node_count() > $node_count_before + 1, 'new nodes were added to graph';
};

subtest 'subsume propagates through chain' => sub {
    # Build: Const_x -> Add -> Return -> Stop
    # Subsume Add with Const_x (simulating x + 0 -> x optimization)
    # All downstream nodes should be cloned with updated references to Const_x

    my $graph = Chalk::IR::Graph->new();

    my $const_x = Chalk::IR::Node->new(
        id => 'const_x',
        op => 'Constant',
        inputs => [],
        attributes => { value => 5, type => 'Int' },
    );
    $graph->add_node($const_x);

    my $const_zero = Chalk::IR::Node->new(
        id => 'const_zero',
        op => 'Constant',
        inputs => [],
        attributes => { value => 0, type => 'Int' },
    );
    $graph->add_node($const_zero);

    my $add = Chalk::IR::Node->new(
        id => 'add_node',
        op => 'Add',
        inputs => ['const_x', 'const_zero'],
        attributes => {},
    );
    $graph->add_node($add);

    my $return = Chalk::IR::Node->new(
        id => 'return_node',
        op => 'Return',
        inputs => ['add_node'],
        attributes => {},
    );
    $graph->add_node($return);

    my $stop = Chalk::IR::Node->new(
        id => 'stop_node',
        op => 'Stop',
        inputs => ['return_node'],
        attributes => {},
    );
    $graph->add_node($stop);

    # const_x initially has 1 use (add_node)
    my $const_x_uses_before = $graph->get_uses('const_x');
    is scalar($const_x_uses_before->@*), 1, 'const_x has 1 use before subsume';

    # For optimization like x + 0 -> x, we want to subsume Add with const_x
    $add->subsume($const_x, $graph);

    # const_x should now have more uses (the new cloned Return node)
    my $const_x_uses_after = $graph->get_uses('const_x');
    ok scalar($const_x_uses_after->@*) > 1, 'const_x has more uses after subsume';
};

subtest 'subsume terminates at nodes with no uses' => sub {
    # Test that recursion terminates when we reach the root (Stop node with no users)

    my $graph = Chalk::IR::Graph->new();

    my $const = Chalk::IR::Node->new(
        id => 'const1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 1, type => 'Int' },
    );
    $graph->add_node($const);

    my $stop = Chalk::IR::Node->new(
        id => 'stop1',
        op => 'Stop',
        inputs => ['const1'],
        attributes => {},
    );
    $graph->add_node($stop);

    my $const2 = Chalk::IR::Node->new(
        id => 'const2',
        op => 'Constant',
        inputs => [],
        attributes => { value => 2, type => 'Int' },
    );
    $graph->add_node($const2);

    # Subsume const with const2
    ok lives { $const->subsume($const2, $graph) }, 'subsume completes without infinite recursion';

    # const2 should now have uses (the new cloned Stop node)
    my $const2_uses = $graph->get_uses('const2');
    ok scalar($const2_uses->@*) > 0, 'const2 has uses after subsume';
};

subtest 'subsume handles multiple users' => sub {
    # Test: one node used by multiple nodes
    # Const_x used by both Add1 and Add2
    # After subsume, Const_z should have uses (new cloned Add nodes)

    my $graph = Chalk::IR::Graph->new();

    my $const_x = Chalk::IR::Node->new(
        id => 'x',
        op => 'Constant',
        inputs => [],
        attributes => { value => 10, type => 'Int' },
    );
    $graph->add_node($const_x);

    my $const_y = Chalk::IR::Node->new(
        id => 'y',
        op => 'Constant',
        inputs => [],
        attributes => { value => 20, type => 'Int' },
    );
    $graph->add_node($const_y);

    my $add1 = Chalk::IR::Node->new(
        id => 'add1',
        op => 'Add',
        inputs => ['x', 'y'],
        attributes => {},
    );
    $graph->add_node($add1);

    my $add2 = Chalk::IR::Node->new(
        id => 'add2',
        op => 'Add',
        inputs => ['x', 'y'],
        attributes => {},
    );
    $graph->add_node($add2);

    # Create replacement
    my $const_z = Chalk::IR::Node->new(
        id => 'z',
        op => 'Constant',
        inputs => [],
        attributes => { value => 30, type => 'Int' },
    );
    $graph->add_node($const_z);

    # x has 2 users: add1 and add2
    my $x_uses_before = $graph->get_uses('x');
    is scalar($x_uses_before->@*), 2, 'x has 2 users before subsume';

    # z has 0 users
    my $z_uses_before = $graph->get_uses('z');
    is scalar($z_uses_before->@*), 0, 'z has 0 users before subsume';

    # Subsume x with z
    $const_x->subsume($const_z, $graph);

    # z should have the users (new cloned Add nodes)
    my $z_uses_after = $graph->get_uses('z');
    is scalar($z_uses_after->@*), 2, 'z has 2 users after subsume (cloned Add nodes)';
};

subtest 'subsume updates attributes with _id suffix' => sub {
    # Test that attributes containing node ID references are updated

    my $graph = Chalk::IR::Graph->new();

    my $region = Chalk::IR::Node->new(
        id => 'region1',
        op => 'Region',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($region);

    my $val1 = Chalk::IR::Node->new(
        id => 'val1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 10, type => 'Int' },
    );
    $graph->add_node($val1);

    my $phi = Chalk::IR::Node->new(
        id => 'phi1',
        op => 'Phi',
        inputs => ['region1', 'val1'],
        attributes => { region_id => 'region1' },
    );
    $graph->add_node($phi);

    # Create replacement region
    my $region2 = Chalk::IR::Node->new(
        id => 'region2',
        op => 'Region',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($region2);

    # Subsume region1 with region2
    $region->subsume($region2, $graph);

    # region2 should have uses (the new cloned Phi node)
    my $region2_uses = $graph->get_uses('region2');
    ok scalar($region2_uses->@*) > 0, 'region2 has uses after subsume';

    # The new Phi node should have region_id = region2
    my @new_phi_ids = grep { /phi1_subsumed/ } $region2_uses->@*;
    ok scalar(@new_phi_ids) > 0, 'found cloned Phi node';

    my $new_phi = $graph->get_node($new_phi_ids[0]);
    is $new_phi->attributes->{region_id}, 'region2', 'cloned Phi has updated region_id attribute';
};
