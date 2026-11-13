# ABOUTME: BEGIN and END through T2: a BEGIN runs first, at the program's start; an
# ABOUTME: END at its exit -- the main line's end, an exit, a die -- last defined first.
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
    q{END { print "end\n" } print "main\n";},
    q{END { print "1\n" } END { print "2\n" } print "main\n";},
    q{our $n = 0; END { print "n=$n\n" } $n = 3;},
    # t/test.pl's: an END reading the file's lexicals a sub sets.
    q{my $ran = 0; my $planned = 2; sub t { $ran++ } END { print $planned == $ran ? "ok\n" : "planned $planned ran $ran\n" } t(); t();},
    q{END { print "e\n" } print "a\n"; exit 3;},
    q{END { print "e\n" } print "a\n"; die "x\n";},
    q{BEGIN { print "b\n" } print "m\n";},
) {
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $src or diag $r->{why} // explain $r;
}

done_testing;
