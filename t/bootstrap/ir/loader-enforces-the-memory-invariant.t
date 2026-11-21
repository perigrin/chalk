# ABOUTME: The loader refuses a wire v2 that breaks the memory invariant (L1-L6 of the wire v2
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
{ "version": 2, "profile": ["mem"], "methods": { "main::__PROGRAM__": { "start": 0, "returns": [21], "nodes": [
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
    [ L6 => qr/Phi#16/, 'a memory Phi with one input for two ways into its Region',
      sub ($n, $all) { $n->{16}{inputs} = [7] } ],
) {
    my ( $rule, $where, $name, $change ) = @$case;
    my $why = refused( bad($change) );
    like( $why, qr/\AGAP: wire invariant \Q$rule\E: main::__PROGRAM__: /, "$rule: $name: refused by its name" );
    like( $why, $where, "$rule: ...naming the node" );
}

# A V1 WIRE IS UPGRADED, NOT HELD TO THE INVARIANT (what v1 left to
# inference is decided by WireUpgrade; stage 6 deletes v1).
my $v1 = decode_json($GOOD);
$v1->{version} = 1;
delete $v1->{profile};
delete $_->{mem_in} for $v1->{methods}{'main::__PROGRAM__'}{nodes}->@*;
is( refused( encode_json($v1) ), '', 'a v1 wire with no memory edges loads (upgraded)' );
done_testing;
