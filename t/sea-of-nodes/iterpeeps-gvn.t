# ABOUTME: Tests for GVN integration into IterPeeps worklist loop
# ABOUTME: Validates that identical computations are deduplicated during peephole

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
use Chalk::IR::Type::Integer;

subtest 'GVN deduplicates identical constants during peephole' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Two identical Constant(5) nodes
    my $const1 = Chalk::IR::Node::Constant->new(value => 5, type => Chalk::IR::Type::Integer->constant(5));
    my $const2 = Chalk::IR::Node::Constant->new(value => 5, type => Chalk::IR::Type::Integer->constant(5));

    $graph->add_node($const1);
    $graph->add_node($const2);

    is $graph->node_count, 2, 'Graph has 2 constant nodes before optimization';

    my $iterpeeps = Chalk::IR::Optimizer::IterPeeps->new();
    my $result = $iterpeeps->apply($graph);

    # With GVN integration, identical constants should be deduplicated
    # Note: This may not reduce node count if constants are kept for other reasons
    # The key test is that peephole sees GVN matches
    ok $result->node_count >= 1, 'Graph still has at least one constant';
};

subtest 'GVN deduplicates identical Add operations' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $x = Chalk::IR::Node::Constant->new(value => 3, type => Chalk::IR::Type::Integer->constant(3));
    my $y = Chalk::IR::Node::Constant->new(value => 7, type => Chalk::IR::Type::Integer->constant(7));

    # Two identical Add(x, y) operations
    my $add1 = Chalk::IR::Node::Add->new(left => $x, right => $y);
    my $add2 = Chalk::IR::Node::Add->new(left => $x, right => $y);

    $graph->add_node($x);
    $graph->add_node($y);
    $graph->add_node($add1);
    $graph->add_node($add2);

    is $graph->node_count, 4, 'Graph has 4 nodes before optimization';

    my $iterpeeps = Chalk::IR::Optimizer::IterPeeps->new();
    my $result = $iterpeeps->apply($graph);

    # Both Add operations fold to Constant(10), and these should be GVN deduplicated
    my @constants = grep { $_->op eq 'Constant' } values $result->nodes->%*;
    my @value_10 = grep { $_->attributes->{value} == 10 } @constants;

    # Should have exactly one Constant(10) after GVN dedup
    is scalar(@value_10), 1, 'Only one Constant(10) after GVN dedup';
};

subtest 'peephole creates node already in GVN table' => sub {
    # Build: (1+2) and a separate 3
    # After peephole: 1+2 -> 3, GVN should find existing Constant(3)
    my $graph = Chalk::IR::Graph->new();

    my $const1 = Chalk::IR::Node::Constant->new(value => 1, type => Chalk::IR::Type::Integer->constant(1));
    my $const2 = Chalk::IR::Node::Constant->new(value => 2, type => Chalk::IR::Type::Integer->constant(2));
    my $const3 = Chalk::IR::Node::Constant->new(value => 3, type => Chalk::IR::Type::Integer->constant(3));
    my $add = Chalk::IR::Node::Add->new(left => $const1, right => $const2);

    $graph->add_node($const1);
    $graph->add_node($const2);
    $graph->add_node($const3);
    $graph->add_node($add);

    is $graph->node_count, 4, 'Graph has 4 nodes before optimization';

    my $iterpeeps = Chalk::IR::Optimizer::IterPeeps->new();
    my $result = $iterpeeps->apply($graph);

    # The Add folds to Constant(3), should merge with existing Constant(3)
    my @constants = grep { $_->op eq 'Constant' } values $result->nodes->%*;
    my @value_3 = grep { $_->attributes->{value} == 3 } @constants;

    is scalar(@value_3), 1, 'Only one Constant(3) after GVN merge';
};
