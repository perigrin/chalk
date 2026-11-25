# ABOUTME: chalk's type lattice (TypeLibrary) and B::SoN's (SoN::IR::Stamp, through PERL5_SON_LIB)
# ABOUTME: are one lattice: same names, same parents, same subtype/join/meet on every pair.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;

use Chalk::Grammar::Perl::TypeLibrary;

# WHY. The two repos keep the lattice twice, by design (B::SoN must not load
# Chalk). Until they read one file (docs/plans/2026-11-25-one-lattice-one-table.md)
# this is what keeps the copies identical: a type added on one side fails here
# until the other has it. The producer's t/lattice-agrees-with-chalk.t is the
# same check from the other side.
my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/SoN/IR/Stamp.pm";
unshift @INC, $SON;
require SoN::IR::Stamp;
my $C = 'Chalk::Grammar::Perl::TypeLibrary';

my $chk = $C->can('lattice_parents')->();
my $son = SoN::IR::Stamp::lattice_parents();

is_deeply( [ sort keys $chk->%* ], [ sort keys $son->%* ], 'the same type names' );
is_deeply( $chk, $son, 'the same parent of every type' );

# Every name either side has, then Maybe[X] for each of them and Maybe of each
# valid Maybe: both sides must accept and refuse the same Maybes.
my %seen;
my @types = grep { !$seen{$_}++ } sort( keys $chk->%*, keys $son->%* );
my ( @valid, @refusal );
for my $t ( @types, map( "Maybe[$_]", @types ) ) {
    my $c = $C->can('is_lattice_type')->($t) ? 1 : 0;
    my $s = eval { SoN::IR::Stamp->new( type => $t ); 1 } ? 1 : 0;
    push @refusal, "$t: chalk=$c B::SoN=$s" if $c != $s;
    push @valid, $t if $c && $s;
}
for my $m ( grep { /\AMaybe\[/ } @valid ) {
    my $t = "Maybe[$m]";
    my $c = $C->can('is_lattice_type')->($t) ? 1 : 0;
    my $s = eval { SoN::IR::Stamp->new( type => $t ); 1 } ? 1 : 0;
    push @refusal, "$t: chalk=$c B::SoN=$s" if $c != $s;
}
is_deeply( \@refusal, [], 'the same names are lattice types, Maybe[...] included' );
ok( ( grep { /\AMaybe\[/ } @valid ) >= 10, 'the pair set holds a Maybe of every scalar type' );

my @diff;
for my $a (@valid) {
    my $sa = SoN::IR::Stamp->new( type => $a );
    for my $b (@valid) {
        my $sb = SoN::IR::Stamp->new( type => $b );
        my @r = (
            [ is_subtype => ( $C->can('is_subtype')->( $a, $b ) ? 1 : 0 ),
                            ( $sa->is_subtype_of($sb) ? 1 : 0 ) ],
            [ join => $C->can('join_types')->( $a, $b ), SoN::IR::Stamp::join( $sa, $sb )->type ],
            [ meet => $C->can('meet_types')->( $a, $b ), SoN::IR::Stamp::meet( $sa, $sb )->type ],
        );
        push @diff, map { "$_->[0]($a, $b): chalk=$_->[1] B::SoN=$_->[2]" }
            grep { $_->[1] ne $_->[2] } @r;
    }
}
diag "  $_" for @diff;
is( scalar @diff, 0, 'is_subtype, join and meet agree on all ' . @valid**2 . ' ordered pairs' );

done_testing;
