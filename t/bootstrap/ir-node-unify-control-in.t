# ABOUTME: Asserts a produce-time-control graph (control set via set_control_in,
# ABOUTME: never flattened into inputs[0]) round-trips through to_json/from_json intact.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Scalar::Util qw(blessed);
use JSON::PP ();
use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use Chalk::IR::Serialize::JSON qw(to_json from_json);

# =============================================================================
# Fixture: a graph built the PRODUCE-TIME way -- control set via
# set_control_in at construction, never flattened into inputs[0]. This is the
# shape i3 moves FromOptree to (GREEN-2): statement-effect nodes carry no
# leading control input; control_in is the only edge to the predecessor.
#
#   sub corpus_case {
#       print "go";       # Print, control_in = Start
#       helper();         # Call,  control_in = Print (chained)
#       my $x = 5;
#       $x;
#   }
#
# The Call is the negative-scenario node: its ONLY inbound edge is
# control_in (no data consumer reads it; a void call has no value use). It
# must still round-trip in a legal topo order, not vanish (dropped from the
# serializable node set) or forward-reference illegally (emitted before its
# control predecessor).
# =============================================================================
sub make_produce_time_graph {
    my $f     = Chalk::IR::NodeFactory->new();
    my $start = $f->make_cfg('Start');

    my $msg   = $f->make('Constant', value => 'go', const_type => 'string');
    my $print = $f->make('Print', inputs => [$msg]);
    $print->set_control_in($start);

    # The Call is control_in-only: no value input, nothing reads its result.
    my $call = $f->make('Call', inputs => [], dispatch_kind => 'direct', name => 'helper');
    $call->set_control_in($print);

    my $five = $f->make('Constant', value => '5', const_type => 'integer');
    my $ret  = $f->make_cfg('Return', inputs => [$five]);
    $ret->set_control_in($call);

    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);
    return ($graph, { print => $print, call => $call, ret => $ret, start => $start });
}

# =============================================================================
# Fixture self-assertion: control lives on control_in, NOT inputs[0], for
# every statement-effect node -- the property this test exists to pin.
# =============================================================================
{
    my ($graph, $parts) = make_produce_time_graph();

    is($parts->{print}->control_in->id, $parts->{start}->id,
        'Print.control_in is Start (not carried in inputs)');
    is(scalar $parts->{print}->inputs->@*, 1,
        'Print.inputs holds only the value (the message), no leading control');

    is($parts->{call}->control_in->id, $parts->{print}->id,
        'Call.control_in is the preceding Print (chained via control_in)');
    is(scalar $parts->{call}->inputs->@*, 0,
        'Call.inputs is empty -- the void call has no data inputs and no '
            . 'leading control; its ONLY inbound edge is control_in');

    is($parts->{ret}->control_in->id, $parts->{call}->id,
        'Return.control_in is the Call (control threads all the way to Return)');
}

# =============================================================================
# Round-trip: to_json(this graph) must carry a control_in wire key (nothing
# to demote -- control was never in inputs), and from_json must decode it
# back onto control_in, INCLUDING the control_in-only Call (it must not
# vanish from the serialized node set, and must not be emitted before Print
# in topo order).
# =============================================================================
{
    my ($graph, $parts) = make_produce_time_graph();
    my $json   = to_json({ corpus_case => $graph });
    my $loaded = from_json($json);
    ok(exists $loaded->{corpus_case}, 'round-trip: graph present after from_json');

    my $g2 = $loaded->{corpus_case};
    my @calls  = grep { blessed($_) && $_->operation eq 'Call'  } $g2->nodes->@*;
    my @prints = grep { blessed($_) && $_->operation eq 'Print' } $g2->nodes->@*;
    is(scalar(@calls), 1, 'the control_in-only Call survives the round-trip (not dropped)');
    is(scalar(@prints), 1, 'the Print survives the round-trip');

    my ($call2)  = @calls;
    my ($print2) = @prints;
    ok(defined $call2->control_in, 'round-tripped Call still carries a control_in edge');
    is($call2->control_in->id, $print2->id,
        'round-tripped Call.control_in still points at the round-tripped Print');
    is(scalar $call2->inputs->@*, 0,
        'round-tripped Call.inputs is still empty -- control did not leak back into inputs');

    # Legal topo order ON THE WIRE: the Call's control predecessor (Print)
    # must be SERIALIZED before the Call, even though NOTHING references the
    # Call via inputs() (its only inbound edge is control_in) -- a topo walk
    # that only follows inputs() has no ordering constraint on a
    # control_in-only node and could legally place it anywhere in the
    # positional-id order, which from_json's single forward pass (JSON.pm's
    # "unresolvable forward input reference is a producer ordering bug" die)
    # would then reject as an illegal forward reference. Re-serialize the
    # ALREADY-LOADED graph and check the wire order directly -- this is the
    # property _all_nodes_topo's control-aware predecessor walk guarantees.
    # (Graph::nodes()'s own cached DFS, unlike _all_nodes_topo, has no
    # control_in awareness and is not itself ordering-authoritative --
    # nothing downstream walks it for control_in ordering; the scheduler
    # walks control_in/inputs directly from Return, never via ->nodes.)
    my $reserialized = to_json({ corpus_case => $g2 });
    my $data2 = JSON::PP->new->decode($reserialized);
    my @wire_nodes = $data2->{methods}{corpus_case}{nodes}->@*;
    my ($print_pos) = map { $_->{id} } grep { $_->{op} eq 'Print' } @wire_nodes;
    my ($call_pos)  = map { $_->{id} } grep { $_->{op} eq 'Call'  } @wire_nodes;
    ok(defined $print_pos && defined $call_pos, 'both nodes located on the re-serialized wire')
        or diag('print_pos=' . ($print_pos // 'undef') . ' call_pos=' . ($call_pos // 'undef'));
    ok($print_pos < $call_pos,
        'Print precedes Call in wire order (legal order for a control_in-only '
            . 'node, not a forward reference)');
}

done_testing();
