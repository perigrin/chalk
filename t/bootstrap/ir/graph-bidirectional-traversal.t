# ABOUTME: Documents that Graph::nodes() does not follow consumers().
# ABOUTME: Phase 7 plan called for bidirectional traversal but the shared
# ABOUTME: Bootstrap singleton factory's process-wide cache means consumer
# ABOUTME: lists can cross graph boundaries, so consumer-following would
# ABOUTME: pull in foreign-class nodes. Restored when each graph owns its
# ABOUTME: own factory.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;

# Graph::nodes() returns the inputs-reachable closure of the cache. A node
# in cache plus its inputs (transitively) all appear in the result.
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

    # Seeding only Add — A and B must still appear because they are
    # inputs of Add and Add is in cache.
    $graph->merge($add);

    my $nodes = $graph->nodes();
    my %ops;
    $ops{$_->operation}++ for $nodes->@*;
    ok($ops{Add}, 'nodes() includes seeded Add');
    is($ops{Constant}, 2,
        'nodes() includes both Constant inputs via inputs() walk');
}

# Per-graph hash-cons scope: nodes from a different graph do not appear,
# because a factory's cache is keyed by content_hash and each Graph has
# its own %cache. (The plan's "bidirectional safety" claim relies on
# per-graph factory ownership, which the Bootstrap singleton breaks.)
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
