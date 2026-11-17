# ABOUTME: Tests per-graph hash-cons isolation across MOP graph-owners: each Method/Sub/Phaser::Adjust
# ABOUTME: holds the body (a graph) the compiler hands it, its own node cache; the MOP makes none.
use 5.42.0;
use utf8;
use lib 'lib', 't/lib';
use Test::Chalk;

use Chalk::MOP;
use Chalk::IR::Node::Constant;
use Chalk::IR::Graph;

# Two methods in the same class: identical Constant content → distinct node objects
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Point');
    my $m1 = $cls->declare_method('one', graph => Chalk::IR::Graph->new);
    my $m2 = $cls->declare_method('two', graph => Chalk::IR::Graph->new);

    my $c1 = $m1->graph->merge(Chalk::IR::Node::Constant->new(
        id    => 'c1',
        value => 0,
    ));
    my $c2 = $m2->graph->merge(Chalk::IR::Node::Constant->new(
        id    => 'c2',
        value => 0,
    ));

    is($c1->content_hash, $c2->content_hash,
       'identical Constant content yields same content_hash');
    isnt(refaddr($c1), refaddr($c2),
         'methods have distinct node objects despite identical content');
}

# Within a single method: merging identical content yields the cached node
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Widget');
    my $method = $cls->declare_method('render', graph => Chalk::IR::Graph->new);

    my $a = $method->graph->merge(Chalk::IR::Node::Constant->new(
        id    => 'a',
        value => 42,
    ));
    my $b = $method->graph->merge(Chalk::IR::Node::Constant->new(
        id    => 'b',
        value => 42,
    ));

    is(refaddr($a), refaddr($b), 'same method deduplicates identical content');
}

# Sub and Method have independent graphs
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Tool');
    my $method = $cls->declare_method('do_it', graph => Chalk::IR::Graph->new);
    my $sub    = $cls->declare_sub('helper', graph => Chalk::IR::Graph->new);

    my $mc = $method->graph->merge(Chalk::IR::Node::Constant->new(
        id    => 'mc',
        value => 1,
    ));
    my $sc = $sub->graph->merge(Chalk::IR::Node::Constant->new(
        id    => 'sc',
        value => 1,
    ));

    isnt(refaddr($mc), refaddr($sc),
         'Method and Sub graphs are isolated');
}

# Phaser::Adjust has its own graph isolated from methods
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Init');
    my $method = $cls->declare_method('run', graph => Chalk::IR::Graph->new);
    my $adjust = $cls->declare_adjust(graph => Chalk::IR::Graph->new);

    my $mc = $method->graph->merge(Chalk::IR::Node::Constant->new(
        id    => 'mc',
        value => 7,
    ));
    my $ac = $adjust->graph->merge(Chalk::IR::Node::Constant->new(
        id    => 'ac',
        value => 7,
    ));

    isnt(refaddr($mc), refaddr($ac),
         'Method and Phaser::Adjust graphs are isolated');
}

# next_cfg_id is independent per graph-owner
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Counters');
    my $m1 = $cls->declare_method('a', graph => Chalk::IR::Graph->new);
    my $m2 = $cls->declare_method('b', graph => Chalk::IR::Graph->new);

    my $m1_id1 = $m1->graph->next_cfg_id;
    my $m1_id2 = $m1->graph->next_cfg_id;
    my $m2_id1 = $m2->graph->next_cfg_id;

    isnt($m1_id1, $m1_id2, 'same method cfg ids are distinct');
    is($m2_id1, $m1_id1,
       'different methods have independent cfg counters starting from same value');
}

# Methods across classes are isolated
{
    my $mop = Chalk::MOP->new;
    my $cls_a = $mop->declare_class('A');
    my $cls_b = $mop->declare_class('B');
    my $ma = $cls_a->declare_method('run', graph => Chalk::IR::Graph->new);
    my $mb = $cls_b->declare_method('run', graph => Chalk::IR::Graph->new);

    my $ca = $ma->graph->merge(Chalk::IR::Node::Constant->new(
        id    => 'ca',
        value => 0,
    ));
    my $cb = $mb->graph->merge(Chalk::IR::Node::Constant->new(
        id    => 'cb',
        value => 0,
    ));

    isnt(refaddr($ca), refaddr($cb),
         'methods in different classes are isolated');
}

done_testing();
