# ABOUTME: A list assign whose targets are kept in memory makes every read at its version before
# ABOUTME: its first store: a target that is also a value read keeps the old value. -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

# Audit 2026-11-22, risk 4 (W2, mixed targets): `($x,$y)=($y,$x)` with \$x
# taken. B::SoN's wire is right -- the $x read at the version before the
# Assign is its target too, and $y's new value -- but T2 made that read the
# target's new element, after the store: `2 2` for perl's `2 1`.
sub verdict ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    return run_probe($pl);
}

for my $case (
    [ q{my ($x,$y)=(1,2); my $r=\$x; ($x,$y)=($y,$x); print "$x $y\n";}, 'aum30: swap, the first target in memory' ],
    [ q{my ($x,$y)=(1,2); my $r=\$y; ($x,$y)=($y,$x); print "$x $y\n";}, 'aum31: swap, the second target in memory' ],
    [ q{my ($x,$y,$z)=(1,2,3); my $r=\$y; ($x,$y,$z)=($z,$x,$y); print "$x $y $z\n";}, 'aum37: a rotation' ],
    [ q{my ($x,$y)=(1,2); my $r=\$x; ($x,$y)=($y,$x); print "$$r $x $y\n";}, 'aun20: read through the reference too' ],
    [ q{my ($x,$y)=(1,2); my $r=\$x; ($x,$y)=(5,$x); print "$x $y\n";}, 'the old value into the second target' ],
) {
    my ( $src, $what ) = @$case;
    my ( $v, $why ) = verdict($src)->@*;
    is( $v, 'SAME', "$what: perl's output" ) or diag "$v $why";
}

done_testing;
