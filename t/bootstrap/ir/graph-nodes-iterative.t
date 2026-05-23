# ABOUTME: Verifies Chalk::IR::Graph::nodes() handles deep chains without recursion warnings.
# ABOUTME: Builds a 5000-deep input chain and asserts walk completes without errors.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(refaddr);
use lib 'lib';

use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;

# Build a deep chain of Constants via shared inputs so that nodes()
# follows a long path during traversal. The naive recursive
# implementation would fire Perl's deep-recursion warning at ~100
# frames; the iterative form must complete cleanly at any depth.
my $factory = Chalk::IR::NodeFactory->new;
my $graph   = Chalk::IR::Graph->new;

my $DEPTH = 5000;  # ~50x Perl's deep-recursion warning threshold

my $prev = $factory->make('Constant', const_type => 'integer', value => '0');
$graph->merge($prev);
for my $i (1..$DEPTH) {
    # Each Add takes the prior node as input — creates a chain of $DEPTH+1
    # nodes connected by inputs[0]. nodes() must walk all of them.
    my $cur = $factory->make('Add',
        inputs => [$prev, $factory->make('Constant',
            const_type => 'integer', value => "$i")],
    );
    $graph->merge($cur);
    $prev = $cur;
}

ok(1, "graph constructed at depth $DEPTH");

# Capture any warnings emitted during the walk. The old recursive form
# would have spewed "Deep recursion on anonymous subroutine".
my @warnings;
local $SIG{__WARN__} = sub { push @warnings, $_[0] };

my $nodes = $graph->nodes;
ok(defined $nodes, "nodes() returned a defined arrayref");

my @deep_warns = grep { /Deep recursion/ } @warnings;
is(scalar @deep_warns, 0,
    "no 'Deep recursion' warnings emitted during walk (got "
    . scalar @warnings . " other warnings)");

# Spot-check: every node we merged should be in the result.
# Total: $DEPTH Add nodes + ($DEPTH+1) Constant nodes (the initial
# value 0, plus values 1..$DEPTH).
my $expected_min = $DEPTH;  # at minimum, every Add node we merged
ok(scalar(@$nodes) >= $expected_min,
    "nodes() returned >= $expected_min nodes (got " . scalar(@$nodes) . ')');

# Cycle-check: no node appears twice.
my %seen;
my @dups;
for my $n (@$nodes) {
    push @dups, $n if $seen{refaddr($n)}++;
}
is(scalar @dups, 0, 'no duplicates in nodes() output');

done_testing();
