# ABOUTME: Tests Chalk::MOP::Class->all_nodes() walks every graph-owner.
# ABOUTME: Per Phase 7, class-level traversal aggregates method + sub graphs.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib';

use Chalk::MOP;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;

ok(Chalk::MOP::Class->can('all_nodes'),
    'MOP::Class has all_nodes() accessor');

# Empty class: no graph-owners, no nodes.
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Empty');

    my @nodes = $cls->all_nodes;
    is(scalar @nodes, 0, 'empty class has no nodes');
}

# Class with two methods, each with a distinct typed node in its
# graph. all_nodes() should reach both.
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('TwoMethods');

    my $g1 = Chalk::IR::Graph->new;
    my $g2 = Chalk::IR::Graph->new;
    my $f  = Chalk::IR::NodeFactory->new;
    $g1->merge($f->make('Constant', const_type => 'integer', value => 11));
    $g2->merge($f->make('Constant', const_type => 'integer', value => 22));

    $cls->declare_method('a', graph => $g1);
    $cls->declare_method('b', graph => $g2);

    my @nodes = $cls->all_nodes;
    ok(scalar @nodes >= 2,
        "all_nodes returns >= 2 nodes (got " . scalar(@nodes) . ")");

    my %seen;
    for my $n (@nodes) {
        $seen{$n->value}++ if blessed($n) && $n->can('value');
    }
    ok($seen{11}, 'all_nodes includes node from method a');
    ok($seen{22}, 'all_nodes includes node from method b');
}

# Subs also contribute graph-owners.
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('WithSub');

    my $g = Chalk::IR::Graph->new;
    my $f = Chalk::IR::NodeFactory->new;
    $g->merge($f->make('Constant', const_type => 'integer', value => 77));

    $cls->declare_sub('helper', graph => $g);

    my @nodes = $cls->all_nodes;
    my %seen = map { ($_->can('value') ? $_->value : '') => 1 } @nodes;
    ok($seen{77}, 'all_nodes reaches into sub graphs');
}

done_testing();
