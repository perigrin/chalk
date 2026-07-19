# ABOUTME: Pins produce-time control_in surviving a forward wire reference:
# ABOUTME: a void statement-effect emitted AFTER its Return consumer must round-trip.

use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Scalar::Util qw(blessed);
use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use Chalk::IR::Serialize::JSON qw(to_json from_json);

# =============================================================================
# THE ROOT CAUSE FIXTURE (`my $c=Counter->new(n=>10); $c->inc; $c->val`):
#
#   Return.control_in = inc-Call   (Return is built BEFORE inc, so inc's
#                                    NodeFactory allocation index is HIGHER
#                                    than Return's -- inc is a forward
#                                    reference from Return's perspective)
#   inc-Call has NO other consumer: it is a VOID method call whose result is
#   discarded; its only anchor into the graph is being Return's control
#   predecessor.
#
# A naive wire encoding (control_in emitted as a plain positional index) puts
# inc's index on Return's node entry BEFORE inc's own node entry has been
# array-order deserialized -- from_json builds nodes strictly in array order,
# so the reference resolves to undef, inc is dropped, and the increment never
# runs (a silent miscompile: $c->val reads the pre-call value).
#
# Build the fixture in the SAME order the bug requires: allocate/emit the
# Return-anchored value chain and Return itself FIRST, and only afterward
# allocate the void Call and attach it via set_control_in -- so serialization
# order (topo or array-emission order) is the thing under test, not
# construction order coincidentally matching a safe order.
# =============================================================================
sub make_forward_control_ref_graph {
    my $f     = Chalk::IR::NodeFactory->new();
    my $start = $f->make_cfg('Start');

    # The value chain ($c->val) and the Return are built and would, absent a
    # fix, be topo-ordered/emitted BEFORE the void inc() call below.
    my $n10 = $f->make('Constant', value => '10', const_type => 'integer');
    my $val = $f->make('Call',
        dispatch_kind => 'method', name => 'val', inputs => [$n10]);
    my $ret = $f->make_cfg('Return', inputs => [$val]);

    # The void statement-effect call ($c->inc;) is allocated AFTER Return and
    # has no data consumer -- its ONLY inbound graph edge is being Return's
    # control_in predecessor (Start -> inc -> Return).
    my $inc = $f->make('Call',
        dispatch_kind => 'method', name => 'inc', inputs => [$n10]);
    $inc->set_control_in($start);
    $ret->set_control_in($inc);

    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);
    return ($graph, { start => $start, val => $val, inc => $inc, ret => $ret });
}

{
    my ($graph, $parts) = make_forward_control_ref_graph();

    # Sanity: the fixture itself has the forward-reference shape (inc has no
    # consumer other than being Return's control_in).
    my @inc_consumers = grep { blessed($_) } $parts->{inc}->consumers->@*;
    ok(!(grep { $_->id eq $parts->{val}->id } @inc_consumers),
        'fixture sanity: inc is not a data-consumer of val (no other anchor)');

    my $json = to_json({ corpus_case => $graph });

    # The wire form must carry inc's control_in edge as its own key on
    # Return's node entry, and inc's own node entry must exist in the nodes
    # array (this is the assertion that would FAIL under a naive wire
    # encoding: inc is either missing from the array, or Return's control_in
    # index points at a position not yet constructed on load).
    use JSON::PP ();
    my $data     = JSON::PP->new->decode($json);
    my $method   = $data->{methods}{corpus_case};
    ok(defined $method, 'corpus_case graph serialized');

    my @nodes = $method->{nodes}->@*;
    my ($inc_wire) = grep {
        $_->{op} eq 'Call' && ($_->{fields}{name} // '') eq 'inc'
    } @nodes;
    ok(defined $inc_wire, 'the void inc() Call is present on the wire at all');

    my ($ret_wire) = grep { $_->{op} eq 'Return' } @nodes;
    ok(defined $ret_wire, 'the Return is present on the wire');
    ok(defined $ret_wire->{control_in}, 'Return carries a control_in wire key');
    is($ret_wire->{control_in}, $inc_wire->{id},
        q{Return's control_in wire key points at inc's wire id});

    # THE KEY ASSERTION: round-trip, and inc must be reachable + resolved
    # (not undef) from the loaded graph.
    my $loaded = from_json($json);
    ok(exists $loaded->{corpus_case}, 'round-trip: graph present after from_json');
    my $loaded_graph = $loaded->{corpus_case};

    my ($loaded_ret) = grep { blessed($_) && $_->operation eq 'Return' }
        $loaded_graph->nodes->@*;
    ok(defined $loaded_ret, 'loaded graph has a Return');

    my $loaded_ctrl = $loaded_ret->can('control_in') ? $loaded_ret->control_in : undef;
    ok(defined $loaded_ctrl, q{loaded Return's control_in resolved (not undef -- the forward ref survived)});
    is($loaded_ctrl->operation, 'Call', 'the resolved control_in is the Call node');
    is($loaded_ctrl->name, 'inc', q{the resolved control_in is specifically the 'inc' call, not dropped/misresolved});

    # The void inc() call must be reachable from Graph::nodes() (i.e. would
    # actually be emitted/lowered by the backend), not merely resolvable as a
    # dangling reference.
    my ($inc_in_loaded) = grep {
        blessed($_) && $_->operation eq 'Call'
            && $_->can('name') && ($_->name // '') eq 'inc'
    } $loaded_graph->nodes->@*;
    ok(defined $inc_in_loaded,
        'the void inc() Call is reachable from Graph::nodes() on the loaded graph (survives to lowering)');
}

done_testing();
