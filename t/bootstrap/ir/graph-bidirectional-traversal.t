# ABOUTME: Tests that Graph::nodes() walks both inputs() and consumers()
# ABOUTME: from cached nodes, with cache-membership filtering on the
# ABOUTME: consumer side to keep the walk graph-local even when consumer
# ABOUTME: pointers cross graph boundaries via the Bootstrap singleton.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;

# Input-direction traversal: a node merged into the graph has its
# transitive inputs visited and included, even when the inputs were
# not separately merged. This is the legacy unidirectional behavior
# and must be preserved.
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

    $graph->merge($add);

    my $nodes = $graph->nodes();
    my %ops;
    $ops{$_->operation}++ for $nodes->@*;
    ok($ops{Add}, 'nodes() includes seeded Add');
    is($ops{Constant}, 2,
        'nodes() includes both Constant inputs via inputs() walk');
}

# Consumer-direction traversal: when a consumer is itself in the
# graph's cache, it must be reachable via nodes() even if the seed
# walk only touches the producer.
{
    my $graph = Chalk::IR::Graph->new;
    my $typed = Chalk::IR::NodeFactory->new;

    my $a = $typed->make('Constant', const_type => 'integer', value => 1);
    my $b = $typed->make('Constant', const_type => 'integer', value => 2);
    my $sum = $typed->make('Add',
        inputs => [undef, $a, $b],
        left   => $a,
        right  => $b,
    );

    # Merge all three nodes into the graph. The walker should find
    # them all whether starting from any of them.
    $graph->merge($a);
    $graph->merge($b);
    $graph->merge($sum);

    my $nodes = $graph->nodes();
    my %ops;
    $ops{$_->operation}++ for $nodes->@*;
    is($ops{Add}, 1, 'in-graph Add is reachable');
    is($ops{Constant}, 2, 'both Constants reachable');
}

# Foreign-consumer filter: a consumer pointer reaching a node that
# is NOT in this graph's cache (e.g., from another graph sharing a
# hash-consed Constant via the Bootstrap singleton) is filtered out.
{
    my $shared_factory = Chalk::IR::NodeFactory->new;

    my $g_a = Chalk::IR::Graph->new;
    my $g_b = Chalk::IR::Graph->new;

    # The shared Constant lives in BOTH graphs' caches (it's
    # hash-consed by the factory so it's the same object).
    my $shared = $shared_factory->make('Constant',
        const_type => 'integer', value => 7);
    $g_a->merge($shared);
    $g_b->merge($shared);

    # Two distinct Add nodes — one for each graph — wrap the shared
    # Constant. They are NOT hash-cons'd identical because their
    # inputs include the (undef) control input which dedups, but
    # let's just construct them as separate Adds with different
    # other operands so each is unique.
    my $extra_a = $shared_factory->make('Constant',
        const_type => 'integer', value => 11);
    my $extra_b = $shared_factory->make('Constant',
        const_type => 'integer', value => 22);
    my $add_a = $shared_factory->make('Add',
        inputs => [undef, $shared, $extra_a],
        left   => $shared,
        right  => $extra_a,
    );
    my $add_b = $shared_factory->make('Add',
        inputs => [undef, $shared, $extra_b],
        left   => $shared,
        right  => $extra_b,
    );

    # Merge add_a only into g_a, add_b only into g_b.
    $g_a->merge($add_a);
    $g_b->merge($add_b);

    # The shared Constant's consumers list contains both Adds.
    my @consumers = $shared->consumers->@*;
    is(scalar @consumers, 2,
        'shared Constant has two Add consumers across both graphs');

    # g_a->nodes() must include add_a but not add_b (which is the
    # foreign consumer reached via $shared->consumers).
    my %ids_a = map { $_->id => 1 } $g_a->nodes->@*;
    my %ids_b = map { $_->id => 1 } $g_b->nodes->@*;

    ok($ids_a{$add_a->id}, 'g_a includes its own Add');
    ok(!$ids_a{$add_b->id},
        'g_a excludes foreign Add reached via shared consumer')
        or diag('g_a saw foreign ' . $add_b->id);

    ok($ids_b{$add_b->id}, 'g_b includes its own Add');
    ok(!$ids_b{$add_a->id},
        'g_b excludes foreign Add reached via shared consumer')
        or diag('g_b saw foreign ' . $add_a->id);
}

done_testing();
