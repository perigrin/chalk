# ABOUTME: A `die` that ends a loop body dies: B::SoN puts its Unwind on the wire as the
# ABOUTME: body's way round, and a loop no way goes round is lowered with no latch. -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

# Audit 2026-11-22, risk 1: the body walk stepped past the `die`, and the
# program printed "after". With it on the wire T2 refused "a loop that never
# goes round"; now every pass dies and the head's phis keep their way in.
sub verdict ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    return run_probe($pl);
}

for my $case (
    [ q{for my $x (1) { die "m\n" } print "after\n";}, 'a foreach whose body is a die' ],
    [ q{my $i = 0; for my $x (1, 2) { $i++; die "m$i\n" } print "after\n";}, 'a die after a statement' ],
    [ q{eval { my $i = 0; while ($i < 3) { $i++; die "w$i\n" } }; print "[$@]\n";}, 'a while in an eval' ],
    [ q{sub t { for my $x (1) { die "t\n" } "end" } print eval { t() } // "died", "\n";}, 'in a sub, caught by its caller' ],
    [ q{eval { die "a\n" for 1; }; print "[$@]\n";}, 'a postfix-for die' ],
) {
    my ( $src, $what ) = @$case;
    my ( $v, $why ) = verdict($src)->@*;
    is( $v, 'SAME', "$what: perl's output" ) or diag "$v $why";
}

done_testing;
