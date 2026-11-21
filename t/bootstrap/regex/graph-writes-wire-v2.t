# ABOUTME: Chalk::Regex::Graph writes its matcher and tr/// graphs as wire v2 itself: memory
# ABOUTME: named by mem_in / mem_out from a MemStart, its binding Assigns records.
use 5.42.0;
use utf8;
use Test2::V0;
use lib 'lib';
use Chalk::Regex::Graph;
use Chalk::IR::Serialize::JSON;

# WHY (docs/plans/2026-11-20-wire-v2.md, stage 6). The loader reads wire v2
# only once v1 is deleted; a regex's graph was written in v1's shape and made
# v2 by Serialize::WireUpgrade, which goes. The graph says its own memory edges:
# each pinned call (push, pop, exit) is a version following the one before it
# on the chain, the Return names the memory at the end, and the Assign that
# binds the arguments is a record.

my @graphs = (
    [ 'scalar a(b)c',   Chalk::Regex::Graph::matcher( 'a(b)c', '', 'scalar' ) ],
    [ 'list (a)|b',     Chalk::Regex::Graph::matcher( '(a)|b', '', 'list' ) ],
    [ 'all \w',         Chalk::Regex::Graph::matcher( '(\w)', 'g', 'all' ) ],
    [ 'gscalar x',      Chalk::Regex::Graph::matcher( 'x', 'g', 'gscalar' ) ],
    [ 'split ,',        Chalk::Regex::Graph::matcher( ',', '', 'split' ) ],
    [ 'subst /g',       Chalk::Regex::Graph::matcher( '(b)', 'g', 'subst', replacement => 'X$1' ) ],
    [ 'subst computed', Chalk::Regex::Graph::matcher( 'b', '', 'subst', computed => 1 ) ],
    [ 'lookahead /i',   Chalk::Regex::Graph::matcher( '(?=a)b|c', 'i', 'scalar' ) ],
    [ 'tr',             Chalk::Regex::Graph::translit( 'a-c', 'x', '' ) ],
);

for my $c (@graphs) {
    my ( $name, $g ) = @$c;
    my @n  = $g->{nodes}->@*;
    my %by = map { ( $_->{id} => $_ ) } @n;
    my $version = sub ($id) { my $x = $by{ $id // '' }; $x && ( $x->{op} eq q(MemStart) || $x->{mem_out} || $x->{op} eq q(Phi) && $x->{fields}{memory} ) };
    is( scalar( grep { $_->{op} eq 'MemStart' } @n ), 1, "$name: one MemStart" );
    my @calls = grep { $_->{op} eq 'Call' && defined $_->{control_in} } @n;
    ok( @calls, "$name: has pinned calls" ) unless $name eq q(tr);   # (tr: none)
    is( [ grep { !$_->{mem_out} || !defined $_->{mem_in} } @calls ], [], "$name: every pinned call is a version that follows one" );
    is( [ grep { !defined $_->{mem_in} } grep { $_->{op} eq 'Return' } @n ], [], "$name: every Return names its memory" );
    is( [ grep { defined $_->{mem_in} && !( $_->{mem_in} < $_->{id} && $version->( $_->{mem_in} ) ) } @n ], [],
        "$name: every mem_in names a version made before it" );
    is( [ grep { !( $_->{fields} // {} )->{record} } grep { $_->{op} eq 'Assign' && !defined $_->{control_in} } @n ], [],
        "$name: an Assign off the chain is a record" );
    is( [ grep { ( $_->{fields} // {} )->{memory_input} } @n ], [], "$name: no v1 memory_input" );
    ok( lives { Chalk::IR::Serialize::JSON::_deserialize_graph($g) }, "$name: loads as it is" ) or note $@;
}

done_testing;
