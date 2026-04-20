# ABOUTME: Tests that Graph->nodes() does not cross method boundaries via consumers().
# ABOUTME: Verifies that shared hash-consed nodes don't pull foreign nodes into a graph.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Constant;

# ============================================================
# Setup: two graphs sharing a hash-consed node as an input to their Returns.
# This simulates what happens in Actions.pm when make('Start') returns the
# same hash-consed Start object used as the control token for multiple
# Return nodes across different methods.
# ============================================================

my $f = Chalk::IR::NodeFactory->new();

# A shared hash-consed node that both Return nodes will use as an input.
# In the real code this is the Start node from make('Start') (hash-consed
# because Start is not in %CFG_OPS in the Bootstrap factory).
my $shared_ctrl = $f->make('Constant', value => '__ctrl__', const_type => 'string');

# Graph A: return_a uses shared_ctrl as control input
my $start_a  = $f->make_cfg('Start');
my $val_a    = $f->make('Constant', value => '1', const_type => 'integer');
my $return_a = $f->make_cfg('Return', inputs => [$shared_ctrl, $val_a]);
my $graph_a  = Chalk::IR::Graph->new(
    start   => $start_a,
    returns => [$return_a],
);

# Graph B: return_b also uses shared_ctrl as control input (different value)
my $start_b  = $f->make_cfg('Start');
my $val_b    = $f->make('Constant', value => '2', const_type => 'integer');
my $return_b = $f->make_cfg('Return', inputs => [$shared_ctrl, $val_b]);
my $graph_b  = Chalk::IR::Graph->new(
    start   => $start_b,
    returns => [$return_b],
);

# Confirm Return nodes are distinct (CFG nodes are not hash-consed)
isnt($return_a->id(), $return_b->id(),
    'Return nodes are distinct (CFG nodes not hash-consed)');

# Confirm shared_ctrl now has both return nodes as consumers (the bug condition)
is(scalar($shared_ctrl->consumers()->@*), 2,
    'shared_ctrl has 2 consumers (both Return nodes registered)');

# ============================================================
# Test: Graph A must not contain Graph B's Return node
# ============================================================

my $nodes_a = $graph_a->nodes();
my %a_ids   = map { $_->id() => 1 } $nodes_a->@*;

ok(!exists $a_ids{$return_b->id()},
    "graph_a->nodes() does not contain return_b")
    or diag("graph_a has " . scalar($nodes_a->@*) . " nodes; return_b id=" . $return_b->id());

my @a_returns = grep { $_ isa Chalk::IR::Node::Return } $nodes_a->@*;
is(scalar @a_returns, 1,
    "graph_a->nodes() contains exactly ONE Return node")
    or diag("Found " . scalar @a_returns . " Return nodes in graph_a");

is($a_returns[0]->id(), $return_a->id(),
    "graph_a's single Return node is return_a");

# ============================================================
# Test: Graph B must not contain Graph A's Return node
# ============================================================

my $nodes_b = $graph_b->nodes();
my %b_ids   = map { $_->id() => 1 } $nodes_b->@*;

ok(!exists $b_ids{$return_a->id()},
    "graph_b->nodes() does not contain return_a")
    or diag("graph_b has " . scalar($nodes_b->@*) . " nodes; return_a id=" . $return_a->id());

my @b_returns = grep { $_ isa Chalk::IR::Node::Return } $nodes_b->@*;
is(scalar @b_returns, 1,
    "graph_b->nodes() contains exactly ONE Return node")
    or diag("Found " . scalar @b_returns . " Return nodes in graph_b");

is($b_returns[0]->id(), $return_b->id(),
    "graph_b's single Return node is return_b");

# ============================================================
# Test: shared_ctrl appears in both graphs (reachable via inputs)
# ============================================================

ok(exists $a_ids{$shared_ctrl->id()},
    "graph_a->nodes() contains shared_ctrl (reachable via inputs from return_a)");
ok(exists $b_ids{$shared_ctrl->id()},
    "graph_b->nodes() contains shared_ctrl (reachable via inputs from return_b)");

done_testing();
