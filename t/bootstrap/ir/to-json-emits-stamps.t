# ABOUTME: to_json emits each node's stamp, so a typed graph survives serialization.
# ABOUTME: Without it chalk cannot hand a typed graph to anything, including a future chalk.

use 5.42.0;
use utf8;
use Test2::V0;
use JSON::PP ();   # no import: its to_json/from_json collide with Chalk's

use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use Chalk::IR::Serialize::JSON qw(to_json from_json);

# `to_json` did not emit a `stamp` field at all -- the string appeared in the
# whole function's range exactly once, inside an error message. So every type
# a graph carried was dropped the moment it was serialized.
#
# Found by round-tripping producer wire through the loader
# (t/bootstrap/ir/loader-reproduces-the-wire.t): 27 stamps lost across four
# small programs, all `wire=Int reloaded=(none)`.
#
# WHY IT MATTERS BEYOND THE ROUND TRIP. `to_json` is the SELF-HOSTING output
# path. A serializer that cannot express the type axis means chalk cannot hand
# a typed graph to anything -- including a future chalk. The type axis existed
# only as long as a graph stayed in memory.
#
# The wire schema already had the field; only chalk's emitter was missing it.
# B::SoN has been sending `stamp` all along, which is why the LOAD side reads
# it and the emit side never did.

sub typed_graph () {
    my $f = Chalk::IR::NodeFactory->new;
    my $a = $f->make('Constant', value => '1', const_type => 'integer');
    $a->set_stamp('Int');
    my $b = $f->make('Constant', value => '2', const_type => 'integer');
    $b->set_stamp('Int');
    my $add = $f->make('Add', inputs => [$a, $b]);
    $add->set_stamp('Int');
    my $ret = $f->make_cfg('Return', inputs => [$add]);
    return Chalk::IR::Graph->new(start => $a, returns => [$ret]);
}

subtest 'a stamp reaches the wire' => sub {
    my $wire = JSON::PP->new->decode(to_json({ 'main::t' => typed_graph() }));
    my @nodes = ( $wire->{methods}{'main::t'}{nodes} // [] )->@*;
    ok scalar(@nodes), 'the graph serialized';

    my ($add) = grep { ( $_->{op} // '' ) eq 'Add' } @nodes;
    ok $add, 'the Add node is on the wire';
    is $add->{stamp}, 'Int', 'and it carries its stamp';
};

subtest 'an unstamped node emits no stamp key' => sub {
    # Absence must stay absent rather than becoming a null or an empty string:
    # the load side distinguishes "no stamp" from "stamped Unknown", and a key
    # that is always present would erase that distinction.
    my $f   = Chalk::IR::NodeFactory->new;
    my $c   = $f->make('Constant', value => '1', const_type => 'integer');
    my $ret = $f->make_cfg('Return', inputs => [$c]);
    my $g   = Chalk::IR::Graph->new(start => $c, returns => [$ret]);

    my $wire = JSON::PP->new->decode(to_json({ 'main::u' => $g }));
    my ($cn) = grep { ( $_->{op} // '' ) eq 'Constant' }
        ( $wire->{methods}{'main::u'}{nodes} // [] )->@*;
    ok $cn, 'the Constant is on the wire';
    ok !exists $cn->{stamp}, 'no stamp key when the node has no stamp';
};

subtest 'the round trip preserves types' => sub {
    # THE POINT. Serialize a typed graph, load it back, and the types survive.
    my $reloaded = from_json(to_json({ 'main::t' => typed_graph() }));
    my ($add) = grep { $_->operation eq 'Add' }
        $reloaded->{'main::t'}->nodes->@*;
    ok $add, 'the Add survived the round trip';
    is $add->stamp, 'Int', 'with its type intact';
};

done_testing;
