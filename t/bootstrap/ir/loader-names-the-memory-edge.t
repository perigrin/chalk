# ABOUTME: A v1 wire loads into the v2 shape: a read's memory is its named mem_in, not an
# ABOUTME: input; a store is a version (mem_out) at the version before it; Return names one.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use Scalar::Util qw(blessed refaddr);
use JSON::PP ();

use Chalk::IR::Serialize::JSON qw(from_json);
use Chalk::IR::Serialize::WireUpgrade;
require Chalk::IR::Analysis;

# WIRE V2, STAGE 2 (docs/plans/2026-11-20-wire-v2.md, section 3 and stage 2):
# chalk's graph takes the v2 shape before the producer writes it. A v1 wire is
# upgraded on load: its trailing positional memory input moves to `mem_in`, a
# pinned store says it is a version (`mem_out`), and each pinned write, sub
# call and Return names the version before it on its control chain.
#
# B::SoN's v1 wire of `my @a = (1,2); $a[0] = 10; print $a[0]` (no MemStart:
# nothing named one), as it wrote it.
my $V1 = <<'JSON';
{"version":1,"source":null,"methods":{"main::__PROGRAM__":{"start":0,"returns":[12],"nodes":[
{"id":0,"inputs":[],"op":"Start"},
{"fields":{"const_type":"undef","value":null},"id":1,"inputs":[],"op":"Constant","stamp":"Undef"},
{"fields":{"const_type":"integer","value":"1"},"id":2,"inputs":[],"op":"Constant","stamp":"Int"},
{"fields":{"const_type":"integer","value":"2"},"id":3,"inputs":[],"op":"Constant","stamp":"Int"},
{"fields":{"sigil":"@","symbol":"a"},"id":4,"inputs":[2,3],"op":"ArrayLiteral","stamp":"Array"},
{"fields":{"const_type":"integer","value":"0"},"id":5,"inputs":[],"op":"Constant","stamp":"Int"},
{"fields":{"kind":"array"},"id":6,"inputs":[4,5],"op":"Subscript","stamp":"Int"},
{"fields":{"const_type":"integer","value":"10"},"id":7,"inputs":[],"op":"Constant","stamp":"Int"},
{"control_in":0,"id":8,"inputs":[6,7],"op":"Assign","stamp":"Int"},
{"fields":{"kind":"array"},"id":9,"inputs":[4,5,8],"op":"Subscript","stamp":"Int"},
{"fields":{"from_repr":"Unknown","to_repr":"Str"},"id":10,"inputs":[9],"op":"Coerce","stamp":"Str"},
{"control_in":8,"id":11,"inputs":[10],"op":"Print","stamp":"Maybe[Boolean]"},
{"control_in":11,"fields":{"implicit":true},"id":12,"inputs":[1],"op":"Return"}
]}}}
JSON

# THE UPGRADE, on the decoded wire.
{
    my $data = JSON::PP::decode_json($V1);
    Chalk::IR::Serialize::WireUpgrade::upgrade($data);
    is( $data->{version}, 2, 'the upgraded wire is version 2' );
    is( join( ',', ( $data->{profile} // [] )->@* ), 'mem', 'its profile is mem' );
    my %by = map { ( $_->{id} => $_ ) } $data->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    my ($ms) = grep { $_->{op} eq 'MemStart' } values %by;
    ok( $ms, 'a MemStart is inserted where the graph had none' );
    is( $ms->{id}, 1, 'right after Start, every later id one up' );
    # (so the read is 10, the place 7, the store 9, the Print 12, the Return 13)
    is( join( ',', $by{10}{inputs}->@* ), '5,6', 'the read Subscript keeps its values only' );
    is( $by{10}{mem_in}, 9, 'the read names the store as its mem_in' );
    ok( !exists $by{7}{mem_in}, 'the place Subscript (the store target) has no mem_in' );
    is( $by{9}{mem_in}, 1, 'the store follows MemStart' );
    ok( $by{9}{mem_out}, 'the store is a version' );
    is( $by{13}{mem_in}, 9, 'the Return names the version at the end' );
    is( $data->{methods}{'main::__PROGRAM__'}{returns}[0], 13, 'the graph names its Return by its new id' );
    ok( !$by{12}{mem_in} && !$by{12}{mem_out}, 'a Print touches no memory' );
}

# THE LOADED GRAPH has the same shape.
{
    my $graphs = from_json($V1);
    my $g = $graphs->{'main::__PROGRAM__'};
    my @all = Chalk::IR::Analysis::_all_graph_nodes($g);
    my @subs = grep { $_->operation eq 'Subscript' } @all;
    my ($read) = grep { blessed( $_->mem_in ) } @subs;
    my ($place) = grep { !blessed( $_->mem_in ) } @subs;
    ok( $read && $place && $read != $place, 'the read and the place are two nodes' );
    is( scalar $read->inputs->@*, 2, 'the read has two inputs' );
    my ($assign) = grep { $_->operation eq 'Assign' } @all;
    ok( blessed( $read->mem_in ) && refaddr( $read->mem_in ) == refaddr($assign), 'its mem_in is the Assign' );
    is( $read->memory_operand, $read->mem_in, 'memory_operand is mem_in' );
    ok( blessed( $assign->mem_in ) && $assign->mem_in->operation eq 'MemStart', "the Assign's mem_in is a MemStart" );
    ok( $assign->mem_out && $assign->is_memory_version, 'the Assign is a version' );
    my $ret = $g->returns->[0];
    ok( blessed( $ret->mem_in ) && refaddr( $ret->mem_in ) == refaddr($assign), "the Return's mem_in is the Assign" );
    ok( ( grep { refaddr($_) == refaddr($read) } $assign->consumers->@* ), 'a mem_in edge is a consumer edge' );
}

done_testing;
