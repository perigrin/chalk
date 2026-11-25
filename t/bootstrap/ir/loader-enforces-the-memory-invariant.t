# ABOUTME: The loader refuses a wire v2 that breaks the memory invariant (L1-L9 of the wire v2
# ABOUTME: plan, section 8.3), by the rule's name, before any graph is made; a good wire loads.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use JSON::PP;
use Chalk::IR::Serialize::JSON;

# WHY. Wire v2 names its memory edges (mem_in, mem_out, a memory Phi's
# inputs); chalk reads them as they come. What the edges must say -- every
# version reached from the sub's end, every edge naming a version -- is
# checked once, on the raw wire (Chalk::IR::Serialize::WireInvariant), so
# no pass meets a graph whose memory chain is broken.
#
# The good wire is B::SoN's for
#   my @a = (1,2); if (@ARGV) { $a[0] = 10 } shift @a; print $a[0];
# written out by hand: each bad one breaks one rule of it.
my $GOOD = <<'JSON';
{ "version": 2, "dowarn": { "on": false, "all_on": false, "all_off": false }, "methods": { "main::__PROGRAM__": { "start": 0, "returns": [21], "nodes": [
   { "id": 0, "inputs": [], "op": "Start" },
   { "fields": { "const_type": "undef", "value": null }, "id": 1, "inputs": [], "op": "Constant", "stamp": "Undef" },
   { "fields": { "const_type": "integer", "value": "1" }, "id": 2, "inputs": [], "op": "Constant", "stamp": "Int" },
   { "fields": { "const_type": "integer", "value": "2" }, "id": 3, "inputs": [], "op": "Constant", "stamp": "Int" },
   { "fields": { "sigil": "@", "symbol": "a" }, "id": 4, "inputs": [2, 3], "op": "ArrayLiteral", "stamp": "Array" },
   { "fields": { "const_type": "integer", "value": "0" }, "id": 5, "inputs": [], "op": "Constant", "stamp": "Int" },
   { "fields": { "package": "main", "sigil": "@", "symbol": "ARGV" }, "id": 6, "inputs": [], "op": "EntryDef", "stamp": "Array" },
   { "id": 7, "inputs": [], "op": "MemStart" },
   { "id": 8, "inputs": [6], "mem_in": 7, "op": "Count", "stamp": "Int" },
   { "control_in": 0, "id": 9, "inputs": [0, 8], "op": "If" },
   { "fields": { "index": 1 }, "id": 10, "inputs": [9], "op": "Proj" },
   { "fields": { "kind": "array" }, "id": 11, "inputs": [4, 5], "op": "Subscript", "stamp": "Int" },
   { "fields": { "const_type": "integer", "value": "10" }, "id": 12, "inputs": [], "op": "Constant", "stamp": "Int" },
   { "fields": { "index": 0 }, "id": 13, "inputs": [9], "op": "Proj" },
   { "control_in": 13, "id": 14, "inputs": [11, 12], "mem_in": 7, "mem_out": true, "op": "Assign", "stamp": "Int" },
   { "head": 9, "id": 15, "inputs": [10, 14], "op": "Region" },
   { "fields": { "memory": true, "predecessors": [10, 13], "region": 15 }, "id": 16, "inputs": [7, 14], "op": "Phi", "stamp": "Unknown" },
   { "control_in": 15, "fields": { "dispatch_kind": "builtin", "name": "shift" }, "id": 17, "inputs": [4], "mem_in": 16, "mem_out": true, "op": "Call", "stamp": "Int" },
   { "fields": { "kind": "array" }, "id": 18, "inputs": [4, 5], "mem_in": 17, "op": "Subscript", "stamp": "Scalar" },
   { "fields": { "from_repr": "Unknown", "to_repr": "Str" }, "id": 19, "inputs": [18], "op": "Coerce", "stamp": "Str" },
   { "control_in": 17, "id": 20, "inputs": [19], "op": "Print", "stamp": "Maybe[Boolean]" },
   { "control_in": 20, "fields": { "implicit": true }, "id": 21, "inputs": [1], "mem_in": 17, "op": "Return" }
] } } }
JSON

# bad($change) -> the good wire with $change applied to its nodes (by id), as JSON
sub bad ($change) {
    my $w = decode_json($GOOD);
    my $nodes = $w->{methods}{'main::__PROGRAM__'}{nodes};
    $change->( { map { ( $_->{id} => $_ ) } @$nodes }, $nodes );
    return encode_json($w);
}

# refused($json) -> the loader's message, or '' where it loaded
sub refused ($json) { return eval { Chalk::IR::Serialize::JSON::from_json($json); 1 } ? '' : $@ }

is( refused($GOOD), '', 'the good wire loads' );

for my $case (
    [ L1 => qr/mem_in Constant#5/, 'a mem_in names no version (a read at a Constant)',
      sub ($n, $all) { $n->{18}{mem_in} = 5 } ],
    [ L2 => qr/Call#17/, 'a version off the control chain (the shift has no control_in)',
      sub ($n, $all) { delete $n->{17}{control_in} } ],
    [ L3 => qr/Return#21/, 'a Return that names no memory',
      sub ($n, $all) { delete $n->{21}{mem_in} } ],
    [ L4 => qr/Call#17/, 'a write no Return reaches backwards (the Return names the memory before the shift)',
      sub ($n, $all) { $n->{21}{mem_in} = 16 } ],
    [ L5 => qr/Assign#22/, 'an Assign that is no record and on neither chain',
      sub ($n, $all) { push @$all, { id => 22, op => 'Assign', inputs => [ 11, 12 ], stamp => 'Int' } } ],
    # (L5 IS HARD since stage 6: a non-record Assign has all three edges)
    [ L5 => qr/Assign#14 is no record and no memory version/, 'a store on the chains that is no version (no mem_out)',
      sub ($n, $all) { delete $n->{14}{mem_out} } ],
    [ L5 => qr/Assign#14 is no record and on no control chain/, 'a store that follows memory and no control',
      sub ($n, $all) { $_->{control_in} = 13 for grep { ($_->{control_in} // -1) == 14 } values %$n; delete $n->{14}{control_in}; delete $n->{14}{mem_out};
                       $n->{15}{inputs} = [10, 13] } ],
    [ L5 => qr/Call#22 is a sub call/, 'a sub call off the control chain',
      sub ($n, $all) { push @$all, { id => 22, op => 'Call', inputs => [], mem_in => 17, fields => { dispatch_kind => 'direct', name => 'main::f' } } } ],
    # (an :lvalue call an Assign stores through is a call too, run where it
    # stands: off the chains, it ran nowhere -- audit 3, corpus 398)
    [ L5 => qr/Call#22 is a sub call and on no control chain/, 'an :lvalue call off the chains, an Assign\'s target',
      sub ($n, $all) { push @$all, { id => 22, op => 'Call', inputs => [], mem_in => 17, fields => { dispatch_kind => 'direct', name => 'main::f' } },
                                     { id => 23, op => 'Assign', inputs => [ 22, 12 ], control_in => 20, mem_in => 17, mem_out => JSON::PP::true }; } ],
    [ L6 => qr/Phi#16/, 'a memory Phi with one input for two ways into its Region',
      sub ($n, $all) { $n->{16}{inputs} = [7] } ],
    # (stage 10: every kind that stores whenever it runs is a version)
    [ L5 => qr/EntryWrite#22 is a store and no memory version/, 'an EntryWrite off both chains',
      sub ($n, $all) { push @$all, { id => 22, op => 'EntryWrite', inputs => [ 6, 12 ] } } ],
    # (stage 10: inputs hold values only -- MemStart and a memory Phi are none)
    [ L9 => qr/Print#20 names MemStart#7 as a value/, 'MemStart as a value input',
      sub ($n, $all) { $n->{20}{inputs} = [7] } ],
    [ L9 => qr/Coerce#19 names Phi#16 as a value/, 'a memory Phi as a value input',
      sub ($n, $all) { $n->{19}{inputs} = [16] } ],
) {
    my ( $rule, $where, $name, $change ) = @$case;
    my $why = refused( bad($change) );
    like( $why, qr/\AGAP: wire invariant \Q$rule\E: main::__PROGRAM__: /, "$rule: $name: refused by its name" );
    like( $why, $where, "$rule: ...naming the node" );
}

# WHAT THE INVARIANT LETS THROUGH, B::SoN's wires of programs it lowers:
#  - a list assignment from a call into `my` scalars declared before it: a
#    store of their slots, on both chains (B::SoN placed it as one in stage
#    6; it had been on the control chain only);
#  - a string eval's trap: its value Phi has one input more than its Region
#    has ways in, as a block eval's join does, until the exceptional edge
#    (stage 8);
#  - an :lvalue call as the location an Assign stores through: a call on
#    both chains, and the Assign after it (L5; audit 3 took the exemption
#    for one off the chains away).
my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
SKIP: {
    skip "perl5-son not found at $SON (set PERL5_SON_LIB)", 3 unless -f "$SON/B/SoN.pm";
    require File::Temp;
    for my $case (
        [ q{sub g { (5, 2) } sub f { my ($lo, $used); ($lo, $used) = g(); $used += 1; "$lo $used" } print f(), "\n";},
          'a list assignment from a call into `my` scalars' ],
        [ q{eval 'package Other; sub g { "g$_[0]" } 1' or die; sub f { return Other::g($_[0]) } print f(2), "\n";},
          'a string eval' ],
        [ q{my $slot = 0; sub slot :lvalue { $slot } slot() = 42; print slot(), "\n";},
          'a store through an :lvalue call' ],
    ) {
        my ( $src, $name ) = @$case;
        my ( $fh, $pl ) = File::Temp::tempfile( SUFFIX => '.pl', UNLINK => 1 );
        print $fh $src;
        close $fh;
        is( refused( scalar qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null) ), '', "$name: its v2 wire loads" );
    }
}

# A GRAPH CHALK WROTE ITSELF (to_json's: `writer: chalk`) is not B::SoN's
# wire and threads no memory: not held to it. ANY OTHER IS HELD, `dowarn` or
# none -- the loader skipped the invariant and WireCheck for a wire with no
# `dowarn` (final audit 2026-11-24, clause 4): taking it away let a broken
# B::SoN wire through.
{
    my $own = decode_json(bad( sub ($n, $all) { delete $n->{21}{mem_in} } ));
    delete $own->{dowarn};
    like( refused( encode_json($own) ), qr/\AGAP: wire invariant L/, 'a wire with no dowarn is held to the invariant' );
    $own->{writer} = 'chalk';
    is( refused( encode_json($own) ), '', 'a wire chalk wrote (writer: chalk) is not' );
    my $w = decode_json( Chalk::IR::Serialize::JSON::to_json( {} ) );
    is( $w->{writer}, 'chalk', 'to_json says chalk wrote it' );
}

# A V1 WIRE IS REFUSED (stage 6 deleted v1; t/bootstrap/ir/loader-refuses-wire-v1.t).
my $v1 = decode_json($GOOD);
$v1->{version} = 1;
like( refused( encode_json($v1) ), qr/\AGAP: wire version 1\b/, 'a v1 wire is refused, not upgraded' );

# THE EVAL'S EXCEPTIONAL EDGE (stage 8): a die's way out is an Exc, and a block eval's
# catch Region merges those edges (t/data/wire-v2-eval-catch-edge.json, the
# plan's section 3.5). L7: every way into a catch Region leads back, by
# control_in, to an Exc. And a trap's join is a merge like any other there:
# L6 lets no value Phi have one more input than its Region has ways in.
{
    my $EVAL = do { local (@ARGV, $/) = 't/data/wire-v2-eval-catch-edge.json'; <> };
    my $bad_eval = sub ($change) {
        my $w = decode_json($EVAL);
        my $nodes = $w->{methods}{'main::__PROGRAM__'}{nodes};
        $change->( { map { ( $_->{id} => $_ ) } @$nodes }, $nodes );
        return encode_json($w);
    };
    is( refused($EVAL), '', 'an eval wire with its catch edge loads' );
    like( refused( $bad_eval->( sub ($n, $all) { $n->{16}{inputs} = [11] } ) ), qr/\AGAP: wire invariant L7: main::__PROGRAM__: Region#16 /,
        'L7: a way into a catch Region that no Exc leads to is refused by its name' );
    like( refused( $bad_eval->( sub ($n, $all) { push @$all, { id => 29, op => 'Phi', inputs => [ 4, 1 ], fields => { region => 19 }, stamp => 'Maybe[Int]' } } ) ),
        qr/\AGAP: wire invariant L6: main::__PROGRAM__: Phi#29 has 2 inputs for 1 ways into Region#19/,
        'L6: an eval join\'s value Phi with one input more than its ways in is refused' );
}

# A WAY OUT WITH NO EVAL (design B1, docs/plans/2026-11-24-copy-and-local-unwind.md
# in B::SoN): `our $g=1; sub f { local $g = 2; 1/$_[0] } eval { f(0) }`. The
# division in f stands under a live local with no eval of f open; its way out
# is Exc#15, the restore of $g (EntryWrite#16), and Unwind#17 marked rethrow.
# L7 holds the edge's shape: an Exc outside an eval ends in its own
# rethrow, and a rethrow is of its own edge's Exc.
{
    my $RE = do { local (@ARGV, $/) = 't/data/wire-v2-rethrow-edge.json'; <> };
    my $bad_re = sub ($change) {
        my $w = decode_json($RE);
        my $nodes = $w->{methods}{'main::f'}{nodes};
        $change->( { map { ( $_->{id} => $_ ) } @$nodes }, $nodes );
        $w->{methods}{'main::f'}{nodes} = [ grep { !$_->{gone} } @$nodes ];
        return encode_json($w);
    };
    is( refused($RE), '', 'a wire with a rethrow edge loads' );
    # (an Exc is in an eval by where its edge goes -- into a catch -- not by
    # a field of what died: a die in a sort comparator inlined in an eval
    # carries no eval_id; chalk-found-gaps:27)
    my $SORT = do { local (@ARGV, $/) = 't/data/wire-v2-eval-die-in-sort-block.json'; <> };
    is( refused($SORT), '', 'an Exc into a catch, of a die with no eval_id, loads' );
    # (that what may die under a live local HAS an edge is not L7's: a
    # local and a value saved and put back by hand are one shape on the
    # wire -- Test::Chalk::subtest's `my $count = $COUNT; ...; $COUNT =
    # $count`. B::SoN makes the edges; SoN::Verify's V10 checks them over
    # the ratchet's wires.)
    is( refused( $bad_re->( sub ($n, $all) { $n->{$_}{gone} = 1 for 15, 16, 17 } ) ), '',
        'L7 does not ask for an edge where a local may be live (the wire cannot say it is a local)' );
    like( refused( $bad_re->( sub ($n, $all) { delete $n->{17}{fields} } ) ),
        qr/\AGAP: wire invariant L7: main::f: Exc#15 .*ends in no rethrow/,
        'L7: an Exc outside an eval ending in a plain die' );
    like( refused( $bad_re->( sub ($n, $all) { $n->{17}{inputs} = [11] } ) ),
        qr/\AGAP: wire invariant L7: main::f: Unwind#17 .*rethrow/,
        'L7: a rethrow not of its own edge\'s Exc' );
}

# A MEMORY EDGE NAMES A VERSION THE WIRE LISTED BEFORE IT. An upgraded v1
# wire could name a merge's memory Phi listed after a node on the control
# chain; B::SoN's v2 never does (it writes a node's memory first), so since
# stage 6 a forward one is refused -- by L8 since every wire keeps it (stage 10).
like( refused( bad( sub ($n, $all) { $n->{8}{mem_in} = 17 } ) ), qr/\AGAP: wire invariant L8: main::__PROGRAM__: Count#8 follows 17 \(mem_in or control_in\), made after it/,
    'a mem_in naming a version listed after it is refused' );
done_testing;
