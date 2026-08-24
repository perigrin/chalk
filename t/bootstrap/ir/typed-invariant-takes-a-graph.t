# ABOUTME: Pins that TypedInvariant's real entry point is a Graph, not a node list.
# ABOUTME: check_nodes is the fragment escape hatch and says so in its own diagnostics.

use 5.42.0;
use utf8;
use Test2::V0;

use Chalk::IR::Graph;
use Chalk::IR::Graph::TypedInvariant;
use Chalk::IR::NodeFactory;

# WHY THE SIGNATURE CHANGED. `check(\@nodes)` could not answer the question the
# analysis pipeline needs answered -- "is this GRAPH well-typed" -- because a
# node list is whatever the caller happened to assemble. The module's own
# comments recorded the consequence three times over; the control-chain leg's
# is the clearest:
#
#   "It only receives the graph's node set (via $nodes->@*), so an effect
#    reachable ONLY through control (not present in that node list) is
#    invisible to it."
#
# So `check($graph)` is now the entry point, and it is what the pipeline exit
# gate (slice 5 of docs/plans/2026-08-24-loader-analysis-pipeline.md) will call.
#
# `check_nodes(\@nodes)` remains for the ~28 unit tests that deliberately check
# a FRAGMENT -- three floating nodes with no Start and no Return, isolating one
# typing rule. Those are not graphs and wrapping them in a synthetic one would
# add a Start and Return the test does not care about, obscuring what it pins.
# The two names answer DIFFERENT questions; that is the whole justification for
# there being two, and it is why the fragment one is not called `check`.

sub add_over ($lrepr, $rrepr, $noderepr) {
    my $f   = Chalk::IR::NodeFactory->new;
    my $lhs = $f->make('Constant', value => '1', const_type => 'integer');
    $lhs->set_representation($lrepr);
    my $rhs = $f->make('Constant', value => '2', const_type => 'integer');
    $rhs->set_representation($rrepr);
    my $add = $f->make('Add', inputs => [$lhs, $rhs]);
    $add->set_representation($noderepr);
    return ($lhs, $rhs, $add);
}

subtest 'check() takes a Graph' => sub {
    my ($lhs, $rhs, $add) = add_over('Int', 'Int', 'Int');
    my $g = Chalk::IR::Graph->new(start => $lhs, returns => [$add]);

    my $result = Chalk::IR::Graph::TypedInvariant->check($g);
    ok $result->{ok}, 'a well-typed graph passes';
    is scalar $result->{violations}->@*, 0, 'with no violations';
};

subtest 'check() finds the same violation a fragment would' => sub {
    # The graph form must not be a weaker check than the fragment form. An
    # Add:Int over a Num operand drops a fraction; both entry points see it.
    my ($lhs, $rhs, $add) = add_over('Int', 'Num', 'Int');
    my $g = Chalk::IR::Graph->new(start => $lhs, returns => [$add]);

    my $via_graph = Chalk::IR::Graph::TypedInvariant->check($g);
    my $via_frag  = Chalk::IR::Graph::TypedInvariant->check_nodes([$lhs, $rhs, $add]);

    ok !$via_graph->{ok}, 'the graph form rejects Add:Int over a Num operand';
    ok !$via_frag->{ok},  'so does the fragment form';
    is scalar $via_graph->{violations}->@*,
       scalar $via_frag->{violations}->@*,
       'both report the same number of violations';
};

subtest 'check() refuses a node list' => sub {
    # The failure that matters: a caller that was not migrated. Passing an
    # arrayref must fail loudly rather than silently checking nothing -- an
    # arrayref has no ->nodes, so a permissive implementation would return
    # ok=1 over zero nodes, which is a vacuous pass.
    my ($lhs, $rhs, $add) = add_over('Int', 'Num', 'Int');

    my $err = dies { Chalk::IR::Graph::TypedInvariant->check([$lhs, $rhs, $add]) };
    ok $err, 'check() on an arrayref dies';
    like $err, qr/check_nodes/,
        'and the message names the fragment entry point';
};

subtest 'check_nodes() still checks a fragment' => sub {
    my ($lhs, $rhs, $add) = add_over('Int', 'Int', 'Int');
    my $result = Chalk::IR::Graph::TypedInvariant->check_nodes([$lhs, $rhs, $add]);
    ok $result->{ok}, 'three floating nodes, no Start, no Return -- still checkable';
};

done_testing;
