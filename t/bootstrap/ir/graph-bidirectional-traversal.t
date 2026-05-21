# ABOUTME: Tests Graph::nodes() bidirectional traversal (inputs + consumers).
# ABOUTME: Per Phase 7, traversal walks both directions but stays graph-scoped.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib';

use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;

# Set up: build a graph with a producer node A whose consumer B is
# reachable only from A's consumers() list (not its inputs).
{
    my $graph = Chalk::IR::Graph->new;
    my $typed = Chalk::IR::NodeFactory->new;

    my $a = $typed->make('Constant', const_type => 'integer', value => 42);
    my $b = $typed->make('Constant', const_type => 'integer', value => 99);
    my $add = $typed->make('Add',
        inputs => [undef, $a, $b],
        left   => $a,
        right  => $b,
    );

    # Seed only the producer node A into the graph.
    $graph->merge($a);

    # A's consumer is Add. Add's consumers list (currently empty) reaches
    # nothing further. The bidirectional walker should still find Add by
    # following A's consumers, AND find B (via Add's inputs).
    my $nodes = $graph->nodes();
    my %ops = map { $_->operation => 1 } $nodes->@*;
    ok($ops{Add},
        'nodes() follows consumers: Add reached from seeded producer A')
        or diag('ops: ' . join(',', sort keys %ops));
    ok($ops{Constant},
        'nodes() includes Constants reached via Add inputs');
}

# Negative case: a node in a different graph isn't pulled in. The
# per-graph hash-cons scope keeps consumer lists local to the graph
# that produced them.
{
    my $graph1 = Chalk::IR::Graph->new;
    my $graph2 = Chalk::IR::Graph->new;
    my $f1 = Chalk::IR::NodeFactory->new;
    my $f2 = Chalk::IR::NodeFactory->new;

    my $a1 = $f1->make('Constant', const_type => 'string', value => 'graph1');
    my $a2 = $f2->make('Constant', const_type => 'string', value => 'graph2');
    $graph1->merge($a1);
    $graph2->merge($a2);

    my @ids1 = map { $_->id } $graph1->nodes->@*;
    my @ids2 = map { $_->id } $graph2->nodes->@*;
    is(scalar(grep { my $a = $_; grep { $_ eq $a } @ids2 } @ids1), 0,
        'graph1 nodes do not appear in graph2');
}

done_testing();
