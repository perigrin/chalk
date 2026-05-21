# ABOUTME: Tests that Graph::nodes() membership-as-authority invariant
# ABOUTME: holds regardless of consumer-pointer scope. The graph's
# ABOUTME: own %cache is the single source of truth for what belongs to
# ABOUTME: the graph; consumer pointers can reference foreign or orphan
# ABOUTME: nodes but those must not appear in nodes().
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(refaddr blessed);
use lib 'lib';

use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::IR::NodeFactory;

# Reset Bootstrap singleton.
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Scenario 1: orphan node sharing a Constant input.
#
# An orphan Return is built via the factory but never merged into the
# graph. The shared Constant's consumers list contains both the real
# Return and the orphan. Whether nodes() walks inputs only or also
# walks consumers, the orphan must not appear because it is not in
# the graph's cache.
{
    my $shared = $factory->make('Constant',
        const_type => 'integer', value => 42);

    my $g = Chalk::IR::Graph->new;
    my $start = $factory->make_cfg('Start');
    my $real_ret = $factory->make_cfg('Return',
        inputs => [$start, $shared]);
    $g->merge($shared);
    $g->merge($real_ret);

    my $orphan_start = $factory->make_cfg('Start');
    my $orphan_ret = $factory->make_cfg('Return',
        inputs => [$orphan_start, $shared]);
    # No $g->merge($orphan_ret) — it's orphaned.

    my @consumers = $shared->consumers->@*;
    is(scalar @consumers, 2,
        'shared Constant has two consumers (real + orphan)');

    my @nodes = $g->nodes->@*;
    my %ids = map { $_->id => 1 } @nodes;
    ok($ids{$real_ret->id}, 'graph includes real Return');
    ok(!$ids{$orphan_ret->id},
        'graph excludes orphan Return (not in cache)')
        or diag('graph saw orphan ' . $orphan_ret->id);
}

# Scenario 2: cross-graph leak via shared Constant.
#
# Two graphs each have their own Return wrapping the same Constant.
# Both Returns are on the Constant's consumer list. graph_a->nodes()
# must contain only graph_a's Return.
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $f = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $shared = $f->make('Constant',
        const_type => 'integer', value => 'hi');

    my $g_a = Chalk::IR::Graph->new;
    my $g_b = Chalk::IR::Graph->new;

    my $start_a = $f->make_cfg('Start');
    my $start_b = $f->make_cfg('Start');
    my $ret_a = $f->make_cfg('Return', inputs => [$start_a, $shared]);
    my $ret_b = $f->make_cfg('Return', inputs => [$start_b, $shared]);

    $g_a->merge($shared); $g_a->merge($ret_a);
    $g_b->merge($shared); $g_b->merge($ret_b);

    my @nodes_a = $g_a->nodes->@*;
    my @nodes_b = $g_b->nodes->@*;
    my %ids_a = map { $_->id => 1 } @nodes_a;
    my %ids_b = map { $_->id => 1 } @nodes_b;

    ok($ids_a{$ret_a->id}, 'graph_a contains its own Return');
    ok($ids_b{$ret_b->id}, 'graph_b contains its own Return');
    ok(!$ids_a{$ret_b->id},
        'graph_a excludes graph_b Return')
        or diag('graph_a saw ' . $ret_b->id);
    ok(!$ids_b{$ret_a->id},
        'graph_b excludes graph_a Return')
        or diag('graph_b saw ' . $ret_a->id);
}

# Scenario 3: bidirectional consumer-reachability within a graph.
#
# Within a single graph, a producer Constant's in-graph consumer must
# be reachable from nodes() even if nothing else seeds the consumer.
# This is the load-bearing Stage 1c invariant — the bidirectional
# walk finds in-graph consumers of in-graph producers.
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $f = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $g = Chalk::IR::Graph->new;
    my $producer = $f->make('Constant',
        const_type => 'integer', value => 100);
    my $start = $f->make_cfg('Start');
    my $consumer = $f->make_cfg('Return',
        inputs => [$start, $producer]);

    # Seed BOTH nodes so the graph's cache holds both.
    $g->merge($producer);
    $g->merge($consumer);

    my @nodes = $g->nodes->@*;
    my %ops = map { $_->operation => 1 } @nodes;
    ok($ops{Constant}, 'nodes() returns the producer Constant');
    ok($ops{Return},   'nodes() returns the in-graph consumer Return');
}

done_testing();
