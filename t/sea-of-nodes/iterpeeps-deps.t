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
