# ABOUTME: Tests for dependency-triggered re-optimization in IterPeeps
# ABOUTME: Validates that peepholes can register deps for remote node changes

use lib 'lib';
use 5.42.0;
use Test2::V0;
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Node;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Graph;
use Chalk::IR::Optimizer::IterPeeps;

subtest 'dependents added to worklist when node changes' => sub {
    # This test verifies the mechanism, not a specific peephole
    # Build a graph where we manually set up dependencies

    my $graph = Chalk::IR::Graph->new();

    my $const1 = Chalk::IR::Node::Constant->new(value => 1, type => 'Integer');
    my $const2 = Chalk::IR::Node::Constant->new(value => 2, type => 'Integer');
    my $add = Chalk::IR::Node::Add->new(left => $const1, right => $const2);

    $graph->add_node($const1);
    $graph->add_node($const2);
    $graph->add_node($add);

    # Manually add a dependency: add depends on const1
    # (In real usage, peephole would call this)
    $const1->add_dep($add->id);

    my @deps = $const1->get_deps();
    is scalar(@deps), 1, 'const1 has one dependent';
    is $deps[0], $add->id, 'dependent is add node';

    my $iterpeeps = Chalk::IR::Optimizer::IterPeeps->new();
    my $result = $iterpeeps->apply($graph);

    # The optimization should complete (add folds to 3)
    my @constants = grep { $_->op eq 'Constant' } values $result->nodes->%*;
    my @value_3 = grep { $_->attributes->{value} == 3 } @constants;

    ok scalar(@value_3) >= 1, 'Add folded to Constant(3)';
};

subtest 'multiple dependencies handled' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $const = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $add1 = Chalk::IR::Node::Add->new(left => $const, right => $const);
    my $add2 = Chalk::IR::Node::Add->new(left => $const, right => $const);

    $graph->add_node($const);
    $graph->add_node($add1);
    $graph->add_node($add2);

    # Both adds depend on const
    $const->add_dep($add1->id);
    $const->add_dep($add2->id);

    my @deps = $const->get_deps();
    is scalar(@deps), 2, 'const has two dependents';

    my $iterpeeps = Chalk::IR::Optimizer::IterPeeps->new();
    my $result = $iterpeeps->apply($graph);

    # Both should fold to 10, and be GVN deduplicated
    my @constants = grep { $_->op eq 'Constant' } values $result->nodes->%*;
    my @value_10 = grep { $_->attributes->{value} == 10 } @constants;

    ok scalar(@value_10) >= 1, 'Both adds folded to Constant(10)';
};

# =============================================================================
# Tests for automatic add_dep() calls by peepholes (Issue #282)
# These tests verify that peepholes register dependencies WITHOUT manual setup
# =============================================================================

subtest 'Add.idealize registers dependency on right child when checking op' => sub {
    # When Add checks if right child is also an Add (for restructuring),
    # it should register a dependency so if right changes, we re-optimize
    my $graph = Chalk::IR::Graph->new();

    my $a = Chalk::IR::Node::Constant->new(value => 1, type => 'Integer');
    my $b = Chalk::IR::Node::Constant->new(value => 2, type => 'Integer');
    my $c = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');

    # Build: a + (b + c) - this triggers right-association check
    my $inner_add = Chalk::IR::Node::Add->new(left => $b, right => $c);
    my $outer_add = Chalk::IR::Node::Add->new(left => $a, right => $inner_add);

    $graph->add_node($a);
    $graph->add_node($b);
    $graph->add_node($c);
    $graph->add_node($inner_add);
    $graph->add_node($outer_add);

    # Call idealize on outer_add - it checks $right->op eq 'Add'
    # and should register a dependency on inner_add
    $outer_add->idealize();

    # Verify dependency was registered
    my @deps = $inner_add->get_deps();
    ok scalar(@deps) >= 1, 'inner_add has at least one dependent after idealize check';
    ok((grep { $_ eq $outer_add->id } @deps), 'outer_add registered as dependent on inner_add');
};

subtest 'Add.idealize registers dependency on left child grandchildren' => sub {
    # When Add checks left->left and left->right for constant combining,
    # it should register dependencies on those grandchildren
    my $graph = Chalk::IR::Graph->new();

    my $x = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $c1 = Chalk::IR::Node::Constant->new(value => 10, type => 'Integer');
    my $c2 = Chalk::IR::Node::Constant->new(value => 20, type => 'Integer');

    # Build: (x + c1) + c2 - this triggers constant combining check
    my $inner_add = Chalk::IR::Node::Add->new(left => $x, right => $c1);
    my $outer_add = Chalk::IR::Node::Add->new(left => $inner_add, right => $c2);

    $graph->add_node($x);
    $graph->add_node($c1);
    $graph->add_node($c2);
    $graph->add_node($inner_add);
    $graph->add_node($outer_add);

    # Call idealize on outer_add - it accesses left->left and left->right
    $outer_add->idealize();

    # Verify dependencies on grandchildren (x and c1)
    my @x_deps = $x->get_deps();
    my @c1_deps = $c1->get_deps();

    # outer_add should register as dependent on x and c1 (the grandchildren)
    ok((grep { $_ eq $outer_add->id } @x_deps), 'outer_add registered as dependent on grandchild x');
    ok((grep { $_ eq $outer_add->id } @c1_deps), 'outer_add registered as dependent on grandchild c1');
};

subtest 'Phi.idealize registers dependencies on data input nodes' => sub {
    # When Phi checks if all data inputs have the same op (operation pulling),
    # it should register dependencies on those nodes
    use Chalk::IR::Node::Region;
    use Chalk::IR::Node::Phi;

    my $graph = Chalk::IR::Graph->new();

    # Create a region with two control inputs
    my $ctrl1 = Chalk::IR::Node::Constant->new(value => 1, type => 'Control');
    my $ctrl2 = Chalk::IR::Node::Constant->new(value => 1, type => 'Control');
    my $region = Chalk::IR::Node::Region->new(inputs => [$ctrl1->id, $ctrl2->id]);

    # Create two Add nodes that the Phi will select between
    my $a = Chalk::IR::Node::Constant->new(value => 1, type => 'Integer');
    my $b = Chalk::IR::Node::Constant->new(value => 2, type => 'Integer');
    my $c = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $d = Chalk::IR::Node::Constant->new(value => 4, type => 'Integer');

    my $add1 = Chalk::IR::Node::Add->new(left => $a, right => $b);
    my $add2 = Chalk::IR::Node::Add->new(left => $c, right => $d);

    # Create Phi that selects between add1 and add2
    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $region->id,
        inputs => [$region->id, $add1->id, $add2->id],
    );

    $graph->add_node($ctrl1);
    $graph->add_node($ctrl2);
    $graph->add_node($region);
    $graph->add_node($a);
    $graph->add_node($b);
    $graph->add_node($c);
    $graph->add_node($d);
    $graph->add_node($add1);
    $graph->add_node($add2);
    $graph->add_node($phi);

    # Call idealize on phi - it checks the op of each data input
    $phi->idealize($graph);

    # Verify dependencies on data input nodes (add1 and add2)
    my @add1_deps = $add1->get_deps();
    my @add2_deps = $add2->get_deps();

    ok((grep { $_ eq $phi->id } @add1_deps), 'phi registered as dependent on add1');
    ok((grep { $_ eq $phi->id } @add2_deps), 'phi registered as dependent on add2');
};
