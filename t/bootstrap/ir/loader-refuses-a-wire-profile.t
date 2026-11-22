# ABOUTME: Wire v2 has no `profile` (wire v2 stage 10): the loader refuses a wire that carries one,
# ABOUTME: by name, holds every wire to all of the invariant (L1-L8), and chalk's own writer writes none.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use JSON::PP;
use Chalk::IR::Serialize::JSON;
use Chalk::IR::Serialize::WireInvariant;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;

# WHY (docs/plans/2026-11-20-wire-v2.md, stage 10). `profile` named the parts
# of v2 a wire obeyed while the migration ran (`mem`, `eval`, `loop`); the
# loader held a wire only to the parts it listed. Every part is v2 now: a wire
# that still lists them was written before the migration closed, and one that
# lists fewer would be let off a part -- refused by name, never read.
my $GOOD = {
    version => 2, dowarn => { on => false, all_on => false, all_off => false },
    methods => { 'main::__PROGRAM__' => { start => 0, returns => [3], nodes => [
        { id => 0, op => 'Start',    inputs => [] },
        { id => 1, op => 'Constant', inputs => [], fields => { const_type => 'integer', value => '1' }, stamp => 'Int' },
        { id => 2, op => 'MemStart', inputs => [] },
        { id => 3, op => 'Return',   inputs => [1], control_in => 0, mem_in => 2 },
    ] } },
};
sub refused ($w) { return eval { Chalk::IR::Serialize::JSON::from_json( encode_json($w) ); 1 } ? '' : $@ }

is( refused($GOOD), '', 'a wire v2 with no profile loads' );
for my $p ( [qw(mem eval loop)], ['mem'], [] ) {
    like( refused( { %$GOOD, profile => $p } ), qr/\AGAP: wire v2 `profile` \[@$p\]: /,
        "a wire with profile [@$p] is refused by name" );
}

# EVERY PART ON EVERY WIRE: what the `loop` and `eval` parts (L8, L7) refuse
# is refused on a wire that lists no part.
my $loop3 = decode_json( encode_json($GOOD) );
my $n = $loop3->{methods}{'main::__PROGRAM__'}{nodes};
splice @$n, 1, 0, { id => 4, op => 'Loop', inputs => [ 0, 0, 0 ] };
like( refused($loop3), qr/\AGAP: wire invariant L8: .*Loop#4 has 3 inputs/, 'L8 with no profile: a Loop of three inputs' );
my $catch = decode_json( encode_json($GOOD) );
push $catch->{methods}{'main::__PROGRAM__'}{nodes}->@*, { id => 5, op => 'Region', inputs => [0], fields => { catch => true } };
like( refused($catch), qr/\AGAP: wire invariant L7: .*Region#5 has a way in \(Start#0\) no Exc leads to/,
    'L7 with no profile: a catch Region no Exc leads to' );

ok( !eval { Chalk::IR::Serialize::WireInvariant->new( profile => ['mem'] ); 1 }, 'WireInvariant takes no profile' );

# CHALK'S OWN WRITER writes none either.
my $f     = Chalk::IR::NodeFactory->new;
my $start = $f->make_cfg('Start');
my $g     = Chalk::IR::Graph->new( start => $start, returns => [ $f->make_cfg( 'Return', inputs => [ $start, $f->make( 'Constant', value => '1', const_type => 'integer' ) ] ) ] );
my $w     = decode_json( Chalk::IR::Serialize::JSON::to_json( { main => $g } ) );
ok( !exists $w->{profile}, 'to_json writes no profile' );
is( $w->{version}, 2, 'and says version 2' );

done_testing;
