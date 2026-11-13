# ABOUTME: A call inference leaves untyped (a sub returning what its caller gave it,
# ABOUTME: called with an untyped argument -- t/test.pl's _ok) is typed by its context.
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
    q{sub f { my ($p) = @_; return $p } sub g { f($_[0]) } print g(1) ? "y\n" : "n\n";},
    q{sub f { my ($p) = @_; return $p } sub g { my ($a, $b) = @_; f($a eq $b) } print g("a", "a") ? "y\n" : "n\n"; print g("a", "b") ? "y\n" : "n\n";},
    q{our $T = 1; sub ok_ { my ($p, $n) = @_; print $p ? "ok $T - $n\n" : "not ok $T - $n\n"; $T = $T + 1; return $p } sub is_ { my ($g, $e, $n) = @_; ok_($g eq $e, $n) } is_(2, 2, "two"); is_(2, 3, "three");},
) {
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $src or diag $r->{why} // explain $r;
}

done_testing;
