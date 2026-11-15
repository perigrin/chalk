# ABOUTME: A computed goto to a label behind it (B::SoN's Loop with no exit): the body runs
# ABOUTME: on to the program's Return, the goto's arm going round, as perl's.
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

for my $case (
    [ q{my $c = $ENV{X} // 0; my $t = $ENV{T} // "TAIL"; print "a"; goto SKIP unless $c; print "b";
        SKIP: print "c"; goto $t; print "d"; TAIL: print "e\n";}, 'a goto past, then one to a label after' ],
    [ q{my $t = $ENV{T} // "B"; A: print "a"; goto $t; print "x"; B: print "b\n";}, 'a label behind not taken' ],
    [ q{my $s = "x"; my $t = $ENV{T} // "E"; S: print $s; goto $t; E: print "$s\n";}, 'a value read after it' ],
    [ q{my $t = $ENV{T} // "E"; S: print "s"; goto $t; E: print "e\n"; for my $i (1 .. 2) { print $i } print "\n";}, 'a loop after it' ],
) {
    my $r = tap("$case->[0]\n");
    is $r->{verdict}, 'SAME', $case->[1] or diag $r->{why} // explain $r;
}

done_testing;
