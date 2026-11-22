# ABOUTME: An aggregate read whole (a package one, a class field) is read at the memory version B::SoN
# ABOUTME: names (its mem_in): a later store does not reach the list. B::SoN -> chalk -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

# W10 (wire v2 stage 7): `my @c = (@st, 2); @st = ()` read @st where the list
# was first used -- after the clear -- and WireCheck refused the shape. B::SoN
# now names the read's version; T2 makes the read there, as a copy of the
# aggregate as it is at that version.
sub verdict ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    return run_probe($pl);
}

for my $case (
    [ q{our @st = (1); my @c = (@st, 2); @st = (); print "@c\n";}, 'nv1: flattened, then cleared' ],
    [ q{our @g = (1,2); my @c = (0, @g); @g = (7); print "@c|@g\n";}, 'nv4: flattened after a constant, then stored' ],
    [ q{our %g = (a => 1); my @k = (%g); %g = (); print scalar(@k), "\n";}, 'nv5: a hash flattened, then cleared' ],
    [ q{our @g = (1,2); sub cp { my @c = (@g, 0); @g = (); return scalar @c } print cp(), scalar(@g), "\n";}, 'nv7: in a sub' ],
    [ q{our @g = (1); sub t { local @g = (@g, 2); return scalar @g } print t(), scalar(@g), "\n";}, 'nv8: into its own local' ],
    [ q{our @g = (1,2); push @g, 3; my @c = (@g); push @g, 4; print "@c|@g\n";}, 'a push either side' ],
    # (wire v2 stage 7, `field`: a field array or hash read whole -- the same
    # read, and it was WRONG at base: `1 2|1 2`)
    [ q{use v5.42; use experimental "class"; class K { field @f = (1); method m { my @a = @f; push @f, 2; my @b = @f; return "@a|@b" } } print K->new->m, "\n";},
        'a field array either side of a push' ],
    [ q{use v5.42; use experimental "class"; class K { field %h = (a => 1); method m { my %c = %h; $h{b} = 2; return join(",", sort keys %c) . "|" . join(",", sort keys %h) } } print K->new->m, "\n";},
        'a field hash either side of a store' ],
    # (`my-aggregate`: a `my` array or hash bound to its slot, read whole --
    # WRONG at base for the array: `1 2|1 2`)
    [ q{my @x; push @x, 1; my @c = @x; push @x, 2; print "@c|@x\n";}, 'a my array copied between two pushes' ],
    [ q{sub f { my %h; $h{a} = 1; my %c = %h; $h{b} = 2; return join(",", sort keys %c) . "|" . join(",", sort keys %h) } print f(), "\n";},
        'a my hash copied between two stores' ],
) {
    my ( $src, $what ) = @$case;
    my ( $v, $why ) = verdict($src)->@*;
    is( $v, 'SAME', "$what: perl's output" ) or diag "$v $why";
}

done_testing;
