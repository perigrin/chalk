# ABOUTME: Wire v1 is gone (wire v2 stage 6): the loader refuses a v1 wire by name, and the
# ABOUTME: v1 reader -- WireUpgrade, Phi::is_memory, Assign::is_placed -- is deleted.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use JSON::PP;
use Chalk::IR::Serialize::JSON;
use Chalk::IR::Node::Phi;
use Chalk::IR::Node::Assign;

# WHY (docs/plans/2026-11-20-wire-v2.md, stage 6; review focus 5). B::SoN
# writes wire v2 only. A v1 wire handed to this loader cannot be read as v2
# (its memory is a positional input, its Phis unflagged): it is refused by
# name, never upgraded or mis-read.
my $v1 = encode_json( { version => 1, source => undef, methods => { 'main::__PROGRAM__' => { start => 0, returns => [2], nodes => [
    { id => 0, op => 'Start',    inputs => [] },
    { id => 1, op => 'Constant', inputs => [], fields => { const_type => 'integer', value => '1' }, stamp => 'Int' },
    { id => 2, op => 'Return',   inputs => [1], control_in => 0 },
] } } } );
sub refused ($json) { return eval { Chalk::IR::Serialize::JSON::from_json($json); 1 } ? '' : $@ }

like( refused($v1), qr/\AGAP: wire version 1\b/, 'a v1 wire: GAP: wire version 1' );
my $none = decode_json($v1);
delete $none->{version};
like( refused( encode_json($none) ), qr/\AGAP: wire version none\b/, 'a wire with no version is not taken for v1' );

# The v1 reader is gone, not merely unused.
ok( !eval { require Chalk::IR::Serialize::WireUpgrade; 1 }, 'Chalk::IR::Serialize::WireUpgrade is deleted' );
ok( !Chalk::IR::Node::Phi->can('is_memory'), 'Phi::is_memory is deleted (a memory Phi is its flag, `memory`)' );
ok( !Chalk::IR::Node::Assign->can('is_placed'), 'Assign::is_placed is deleted (L5: an Assign is a record or on both chains)' );

done_testing;
