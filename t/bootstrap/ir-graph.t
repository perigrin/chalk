# ABOUTME: Tests for Chalk::IR::Graph container.
# ABOUTME: Verifies start/returns fields, topological sort, and node lookup.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;

my $f = Chalk::IR::NodeFactory->new();

my $start = $f->make_cfg('Start');
my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
my $add = $f->make('Add', inputs => [$c1, $c2]);
my $ret = $f->make_cfg('Return', inputs => [$start, $add]);

my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);
isa_ok($graph, 'Chalk::IR::Graph');
is($graph->start(), $start, 'graph start');
is(scalar $graph->returns()->@*, 1, 'graph has one return');

my $nodes = $graph->nodes();
ok(scalar $nodes->@* >= 4, 'nodes() finds at least 4 nodes');

my %ops = map { $_->operation() => 1 } $nodes->@*;
ok($ops{Start}, 'Start in topo sort');
ok($ops{Constant}, 'Constant in topo sort');
ok($ops{Add}, 'Add in topo sort');
ok($ops{Return}, 'Return in topo sort');

# Topological order: inputs before consumers
my %pos;
for my $i (0 .. $nodes->$#*) {
    $pos{$nodes->[$i]->id()} = $i;
}
ok($pos{$c1->id()} < $pos{$add->id()}, 'Const(1) before Add');
ok($pos{$c2->id()} < $pos{$add->id()}, 'Const(2) before Add');

# Graph with Unwind (dual exits)
my $exc = $f->make('Constant', value => 'error', const_type => 'string');
my $unw = $f->make_cfg('Unwind', inputs => [$start, $exc]);
my $graph2 = Chalk::IR::Graph->new(start => $start, returns => [$ret, $unw]);
is(scalar $graph2->returns()->@*, 2, 'graph with normal + exceptional exit');

# Schedule field: default is empty hashref
my $graph3 = Chalk::IR::Graph->new(start => $start, returns => []);
is(ref($graph3->schedule()), 'HASH', 'schedule() returns hashref by default');
is(scalar keys $graph3->schedule()->%*, 0, 'default schedule is empty');

# Schedule field: populated with cfg_state entries
my $if_node = $f->make_cfg('Start');   # Reuse Start as stand-in for If node in test
my %cfg_state = (if_node => $if_node, then_stmts => [], else_stmts => []);
my $key = refaddr($c1);
my $graph4 = Chalk::IR::Graph->new(
    start    => $start,
    returns  => [],
    schedule => { $key => \%cfg_state },
);
is(ref($graph4->schedule()), 'HASH', 'graph schedule() is a hashref');
is(scalar keys $graph4->schedule()->%*, 1, 'schedule has one entry');
is($graph4->schedule()->{$key}, \%cfg_state, 'schedule maps key to cfg_state');

done_testing();
