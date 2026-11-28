# ABOUTME: An array made of a repetition of constants, `my @t = (0) x 3`, is made before the
# ABOUTME: if or loop that stores into it, as a list of constants is (stevan/curly brainfuck.pl).
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
use Chalk::CodeGen::Harness::LLI;
Chalk::CodeGen::Harness::LLI->lli;
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

# THE GAP: agg_settle made an array before an If or a Loop only where each
# input was a Constant or made already; `(0) x 3` is a Repeat of constants
# nothing made yet, so the array was first made in the arm: refused.
for my $src (
    'my @t = (0) x 3; if ($ARGV[0] // 1) { $t[1] = 5 } print "@t\n";',
    'my @t = (0) x 3; my $i = 0; while ($i < 3) { $t[$i] = 5; $i++ } print "@t\n";',
    'my @t = (0) x 3; my $i = 0; while ($i < 3) { if ($i == 1) { $t[$i] = 5 } $i++ } print "@t\n";',
    'my @t = (1, 2) x 2; for my $i (0 .. $#t) { $t[$i] *= 2 if $i % 2 } print "@t\n";',
) {
    my $r = tap($src);
    is $r->{verdict}, 'SAME', "as perl through T2: $src" or diag $r->{why} // explain $r;
}
done_testing;
