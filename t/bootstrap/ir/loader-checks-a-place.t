# ABOUTME: The loader's L10: a place (fields.place, aliases-as-places) is storage on no chain, of an
# ABOUTME: access kind, used only where perl binds an alias -- a sub call or an alias list.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use Chalk::IR::Serialize::WireInvariant;

# good() -> a graph passing `our $x` to `main::f` as its place, and listing it
# in a foreach's alias list with an element `$a[2]` perl's alias makes exist
sub good () {
    return { nodes => [
        { id => 0, op => 'Start', inputs => [] },
        { id => 1, op => 'MemStart', inputs => [] },
        { id => 2, op => 'EntryDef', inputs => [], fields => { package => 'main', sigil => '$', symbol => 'x', place => 1 } },
        { id => 3, op => 'Call', inputs => [2], control_in => 0, mem_in => 1, mem_out => 1, fields => { dispatch_kind => 'direct', name => 'main::f' } },
        { id => 4, op => 'ArrayLiteral', inputs => [], fields => { sigil => '@', symbol => 'a' } },
        { id => 5, op => 'Constant', inputs => [], fields => { const_type => 'integer', value => 2 } },
        { id => 6, op => 'Subscript', inputs => [4, 5], fields => { kind => 'array', place => 1, vivify => 1 } },
        { id => 7, op => 'ArrayLiteral', inputs => [2, 6], control_in => 3, mem_in => 3, mem_out => 1 },
        { id => 8, op => 'Return', inputs => [], control_in => 7, mem_in => 7 },
    ] };
}
sub refused ($g) { return eval { Chalk::IR::Serialize::WireInvariant->new->check( 'main::__PROGRAM__', $g ); 1 } ? '' : $@ }

is( refused( good() ), '', 'a place passed to a call and listed in an alias list: loads' );

for my $case (
    [ 'a place that reads memory', sub ($n) { $n->[2]{mem_in} = 1 } ],
    [ 'a place on the control chain', sub ($n) { $n->[6]{control_in} = 0 } ],
    [ 'a place of no access kind', sub ($n) { $n->[5]{fields}{place} = 1 } ],
    [ 'a place read as a value', sub ($n) { push @$n, { id => 9, op => 'Coerce', inputs => [2], fields => { from_repr => 'Scalar', to_repr => 'Str' } } } ],
    [ 'a place in a named array', sub ($n) { $n->[7]{fields} = { sigil => '@', symbol => 'b' } } ],
    [ 'a vivifying place that is no element', sub ($n) { $n->[2]{fields}{vivify} = 1 } ],
) {
    my ( $what, $change ) = @$case;
    my $g = good();
    $change->( $g->{nodes} );
    like( refused($g), qr/GAP: wire invariant L10: /, "refused by L10: $what" );
}

done_testing;
