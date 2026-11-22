# ABOUTME: A callee's store to $_ inside a foreach is a store to the element $_ aliases, whether
# ABOUTME: or not the loop reads $_ itself: perl's @l changes. B::SoN -> chalk -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

# Audit 2026-11-22: T2 took $_ for an alias only where the program also read
# it, so `for (@l) { f() } sub f { $_ = 9 }` stored into $main::_ and left
# @l as it was. (One that reads $_ after the call is refused by name: B::SoN
# folds that read to the element at the version before the call.)
sub verdict ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    return run_probe($pl);
}

for my $case (
    [ q{my @l = (1,2); for (@l) { inner(); } sub inner { $_ = 9 } print "@l\n";}, 'aum50: a my array' ],
    [ q{our @l = (1,2); for (@l) { inner(); } sub inner { $_ = 9 } print "@l\n";}, 'aum56: a package array' ],
    [ q{my @l = (1,2); for (@l) { my $o = $_; inner(); print "$o$_ " } sub inner { $_ = 9 } print "\n";}, 'aum51: read after the call' ],
) {
    my ( $src, $what ) = @$case;
    my ( $v, $why ) = verdict($src)->@*;
    like( $v, qr/\A(?:SAME|REFUSED)\z/, "$what: perl's output, or refused by name" ) or diag "$v $why";
}

done_testing;
