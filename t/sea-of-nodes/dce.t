# ABOUTME: Tests for Dead Code Elimination (DCE) in the IR Graph
# ABOUTME: Validates that unused nodes are properly cleaned up from the graph

use lib 'lib';
use v5.42;
use Test::More;

use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Node::Constant');
use_ok('Chalk::IR::Node::Add');

# =============================================================================
# Helper functions
# =============================================================================

use Chalk::IR::Type::Integer;

sub make_constant {
    my ($value) = @_;
    return Chalk::IR::Node::Constant->new(value => $value, type => Chalk::IR::Type::Integer->constant($value));
}

# =============================================================================
# Basic Graph use counting tests
# =============================================================================

subtest 'Graph tracks use counts correctly' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create nodes: outer Add uses inner Add, inner Add uses two Constants
    my $c1 = make_constant(1);
    my $c2 = make_constant(2);
    my $add_inner = Chalk::IR::Node::Add->new(left => $c1, right => $c2);
    my $c3 = make_constant(3);
    my $add_outer = Chalk::IR::Node::Add->new(left => $add_inner, right => $c3);

    # Add nodes to graph
    $graph->add_node($c1);
    $graph->add_node($c2);
    $graph->add_node($add_inner);
    $graph->add_node($c3);
    $graph->add_node($add_outer);

    # Check use counts
    my $c1_uses = $graph->get_uses($c1->id);
    my $c2_uses = $graph->get_uses($c2->id);
    my $add_inner_uses = $graph->get_uses($add_inner->id);
    my $c3_uses = $graph->get_uses($c3->id);
    my $add_outer_uses = $graph->get_uses($add_outer->id);

    is(scalar(@$c1_uses), 1, 'c1 has 1 use (from inner Add)');
    is(scalar(@$c2_uses), 1, 'c2 has 1 use (from inner Add)');
    is(scalar(@$add_inner_uses), 1, 'inner add has 1 use (from outer Add)');
    is(scalar(@$c3_uses), 1, 'c3 has 1 use (from outer Add)');
    is(scalar(@$add_outer_uses), 0, 'outer add has 0 uses (root node)');
};

# =============================================================================
# DCE: remove_node method tests
# =============================================================================

subtest 'remove_node removes node from graph' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $c1 = make_constant(1);
    $graph->add_node($c1);

    is($graph->node_count(), 1, 'Graph has 1 node before removal');

    $graph->remove_node($c1->id);

    is($graph->node_count(), 0, 'Graph has 0 nodes after removal');
    ok(!$graph->get_node($c1->id), 'Node is no longer accessible');
};

subtest 'remove_node updates use lists' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $c1 = make_constant(1);
    my $c2 = make_constant(2);
    my $add = Chalk::IR::Node::Add->new(left => $c1, right => $c2);

    $graph->add_node($c1);
    $graph->add_node($c2);
    $graph->add_node($add);

    # c1 and c2 should have add as a user
    is(scalar(@{$graph->get_uses($c1->id)}), 1, 'c1 has 1 use before removal');
    is(scalar(@{$graph->get_uses($c2->id)}), 1, 'c2 has 1 use before removal');

    # Remove add node - should update c1 and c2 use lists
    $graph->remove_node($add->id);

    is(scalar(@{$graph->get_uses($c1->id)}), 0, 'c1 has 0 uses after add removed');
    is(scalar(@{$graph->get_uses($c2->id)}), 0, 'c2 has 0 uses after add removed');
};

# =============================================================================
# DCE: kill method tests
# =============================================================================

subtest 'kill removes unused node' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $c1 = make_constant(1);
    $graph->add_node($c1);

    is($graph->node_count(), 1, 'Graph has 1 node before kill');

    # Kill the constant (it has no users)
    $graph->kill($c1->id);

    is($graph->node_count(), 0, 'Graph has 0 nodes after kill');
};

subtest 'kill recursively removes unused inputs' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $c1 = make_constant(1);
    my $c2 = make_constant(2);
    my $add = Chalk::IR::Node::Add->new(left => $c1, right => $c2);

    $graph->add_node($c1);
    $graph->add_node($c2);
    $graph->add_node($add);

    is($graph->node_count(), 3, 'Graph has 3 nodes before kill');

    # Kill add - should recursively kill c1 and c2 since they become unused
    $graph->kill($add->id);

    is($graph->node_count(), 0, 'Graph has 0 nodes after recursive kill');
};

subtest 'kill does not remove inputs still in use' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $c1 = make_constant(1);
    my $c2 = make_constant(2);
    my $add1 = Chalk::IR::Node::Add->new(left => $c1, right => $c2);
    # Note: Once GVN (Global Value Numbering) is implemented, duplicate
    # constant values would be interned to the same node automatically.
    my $c3 = make_constant(3);
    my $add2 = Chalk::IR::Node::Add->new(left => $c1, right => $c3);

    $graph->add_node($c1);
    $graph->add_node($c2);
    $graph->add_node($add1);
    $graph->add_node($add2);
    $graph->add_node($c3);

    my $initial_count = $graph->node_count();

    # Kill add1 - c2 should be killed (only user), but c1 should remain (used by add2)
    $graph->kill($add1->id);

    ok(!$graph->get_node($add1->id), 'add1 is removed');
    ok(!$graph->get_node($c2->id), 'c2 is removed (no more users)');
    ok($graph->get_node($c1->id), 'c1 remains (still used by add2)');
};

# =============================================================================
# DCE integration with peephole optimization
# =============================================================================

subtest 'DCE after constant folding cleans up original nodes' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $c1 = make_constant(1);
    my $c2 = make_constant(2);
    my $add = Chalk::IR::Node::Add->new(left => $c1, right => $c2);

    $graph->add_node($c1);
    $graph->add_node($c2);
    $graph->add_node($add);

    is($graph->node_count(), 3, 'Graph has 3 nodes before optimization');

    # Peephole folds add to constant(3)
    my $folded = $add->peephole();
    is($folded->op, 'Constant', 'Add folded to Constant');
    is($folded->value, 3, 'Folded value is 3');

    # Replace add with folded in graph (simulating what would happen during optimization)
    $graph->add_node($folded);

    # Kill the original add (which is now dead code)
    $graph->kill($add->id);

    # Only the folded constant should remain
    is($graph->node_count(), 1, 'Graph has 1 node after DCE');
    ok($graph->get_node($folded->id), 'Folded constant remains in graph');
};

done_testing();
