# ABOUTME: Tests for Chalk::IR::Graph::merge() hash-consing and next_cfg_id().
# ABOUTME: Verifies per-graph isolation and content-hash deduplication within a graph.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Graph;
use Chalk::IR::Node::Constant;

# merge returns the node on first add
{
    my $graph = Chalk::IR::Graph->new;
    my $node = Chalk::IR::Node::Constant->new(
        id    => 'c1',
        value => 42,
    );
    my $result = $graph->merge($node);
    isa_ok($result, 'Chalk::IR::Node::Constant');
    is($result->value, 42, 'merge returns the merged node');
}

# merge deduplicates on content_hash within same graph
{
    my $graph = Chalk::IR::Graph->new;
    my $a = Chalk::IR::Node::Constant->new(
        id    => 'a',
        value => 0,
    );
    my $b = Chalk::IR::Node::Constant->new(
        id    => 'b',
        value => 0,
    );

    # Both have the same content_hash
    is($a->content_hash, $b->content_hash, 'identical Constant nodes have same content_hash');

    my $first  = $graph->merge($a);
    my $second = $graph->merge($b);
    is(refaddr($first), refaddr($second), 'merge returns cached node on duplicate content_hash');
}

# Per-graph isolation: same node content in different graphs yields distinct objects
{
    my $graph_a = Chalk::IR::Graph->new;
    my $graph_b = Chalk::IR::Graph->new;

    my $node_a = $graph_a->merge(Chalk::IR::Node::Constant->new(
        id    => 'ca',
        value => 0,
    ));
    my $node_b = $graph_b->merge(Chalk::IR::Node::Constant->new(
        id    => 'cb',
        value => 0,
    ));

    isnt(refaddr($node_a), refaddr($node_b), 'identical content across graphs are distinct objects');
}

# next_cfg_id allocates unique ids within a graph
{
    my $graph = Chalk::IR::Graph->new;
    my $id1 = $graph->next_cfg_id;
    my $id2 = $graph->next_cfg_id;
    my $id3 = $graph->next_cfg_id;

    isnt($id1, $id2, 'cfg ids are distinct');
    isnt($id2, $id3, 'cfg ids keep incrementing');
}

# Different graphs have independent cfg counters
{
    my $graph_a = Chalk::IR::Graph->new;
    my $graph_b = Chalk::IR::Graph->new;

    my $a1 = $graph_a->next_cfg_id;
    my $a2 = $graph_a->next_cfg_id;
    my $b1 = $graph_b->next_cfg_id;

    # Both graphs start from 1; they allocate independently
    is($b1, $a1, 'separate graphs have independent cfg counters starting from same point');
}

done_testing();
