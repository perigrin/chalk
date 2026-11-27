# ABOUTME: `$_` read where a foreach aliases it is the element itself, as it is when read: a store to
# ABOUTME: the element first, in the body or a callee, is seen. B::SoN -> chalk -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

# Fifth final audit, Q17 (vt48): `our @a = (1,2,3); sub f { $a[0]++; $_ }
# ... for (@a) { $t .= f() }` printed `123` for `223`. Where nothing stored
# into $_ by its name, T2 kept the element's value in $_ at each pass's start:
# a store to the element by another name was not seen through it.
sub verdict ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    return run_probe($pl);
}

for my $src (
    q{our @a = (1,2,3); sub f { $a[0]++; $_ } my $t = ""; for (@a) { $t .= f() } print "$t\n";},     # vt48
    q{our @a = (1,2,3); sub f { $a[0] = 7; $_ } my $t = ""; for (@a) { $t .= f() } print "$t\n";},
    q{our @a = (1,2,3); sub f { $_ } my $t = ""; for (@a) { $a[0]++; $t .= f() } print "$t\n";},
    q{my @a = (1,2,3); sub f { $a[0]++; $_ } my $t = ""; for (@a) { $t .= f() } print "$t\n";},
    q{our @a = (1,2,3); sub f { $a[0]++; 0 } my $t = ""; for (@a) { f(); $t .= $_ } print "$t\n";},
) {
    my ( $v, $why ) = verdict($src)->@*;
    like( $v, qr/\A(?:SAME|REFUSED)\z/, "perl's answer or refused by name: $src" ) or diag "$v $why";
}

# (Q17's other single, vt87: a loop's `my` read before a call that stores it
# through @_ -- B::SoN names the version before the call; T2 made the read
# where it was first used, after the call, `202` for `102`)
for my $src (
    q{sub f { $_[0]++; 0 } my @t; for my $i (1..3) { my $y = $i; push @t, "$y" . f($y) . "$y" } print "@t\n";},
    q{sub f { $_[0] = 9; 0 } for my $i (1..2) { my $y = $i; my $s = "$y" . f($y) . "$y"; print "$s;" } print "\n";},
) {
    my ( $v, $why ) = verdict($src)->@*;
    is( $v, 'SAME', "perl's answer: $src" ) or diag $why;
}

done_testing;
