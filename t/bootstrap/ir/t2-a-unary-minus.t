# ABOUTME: Unary minus through T2, perl's way: a number negated; a string that
# ABOUTME: begins with a letter gets a "-", one with a "+" has it turned to "-".
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

for my $src (
    q{sub f { my $x = shift; return - $x } print f(3), ",", f(-4), ",", f(2.5), ",", f("7"), ",", f("-2"), ",", f("abc"), ",", f("+q"), ",", f("_z"), ",", f("-"), ",", f(0.0), "\n";},
    q{my $n = 5; my $m = -$n; print $m + 1, "\n";},
    q{sub f { my ($s, $k) = @_; return substr($s, 0, - $k) } print f("abcdef", 2), "\n";},
) {
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $src or diag $r->{why} // explain $r;
}

done_testing;
