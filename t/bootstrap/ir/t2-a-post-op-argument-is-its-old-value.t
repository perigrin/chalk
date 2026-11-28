# ABOUTME: A `my` scalar's post-increment or post-decrement handed to a sub is the old value, a
# ABOUTME: copy: B::SoN reads it at the version before the store, and T2 made it the variable.
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

# THE DEFECT (probe vvp94, promotion off): `f(--$x, $x--)` printed `-1-1` for
# perl's `-10`. With the argument not promoted, $x is a `my` kept in memory;
# B::SoN passes `--$x` as its place and `$x--` as a read at the version before
# the decrement's store. T2 passed every memory read of a `my` as the variable
# (an SRef), so the callee read it after the store. A package scalar's read at
# an older version than the call's was already a copy (audit 2, K6).
local $ENV{SON_NO_PROMOTE} = 1;
for my $src (
    'my $x = 1; sub f { $_[0] . $_[1] } print f(--$x, $x--), "\n";',
    'my $x = 1; sub f { $_[0] . $_[1] } print f(++$x, $x++), "\n";',
    'my $x = 5; my $r = \$x; sub g { $_[0] . $_[1] } print g($x--, $x), "\n";',
) {
    my $r = tap($src);
    is $r->{verdict}, 'SAME', "as perl through T2, promotion off: $src" or diag $r->{why} // explain $r;
}
done_testing;
