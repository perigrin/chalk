# ABOUTME: Arrays with elements that do not exist (holes) through T2: a store past the
# ABOUTME: end, `$#a = N` growing or shrinking, exists, and a copy making them exist.
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

my $ex = q{sub ex { my $r = shift; join(",", map { exists $r->[$_] ? "e" : "n" } 0 .. $#$r) } };
for my $src (
    q{my @b; $b[3] = 1; print scalar(@b), " ", exists $b[1] ? "e" : "n", exists $b[3] ? "e" : "n", defined $b[1] ? "d" : "u", "\n";},
    q{my @a = (1, 2, 3); $#a = -1; print scalar(@a), "\n";},
    q{my @a = (1, 2, 3); $#a = -5; print scalar(@a), "\n";},
    q{my @a = (1 .. 5); my $n = $ENV{NOPE} // 1; $#a = $n; print "@a\n";},
    q{my @c = (1); $#c = 3; print scalar(@c), exists $c[0] ? "e" : "n", exists $c[2] ? "e" : "n", "\n"; my @d = @c; print exists $d[2] ? "e" : "n", defined $d[2] ? "d" : "u", "\n";},
    q{my @f = (5); $#f = 2; my $p = pop @f; print defined $p ? "d" : "u", scalar(@f), "\n"; $#f = 4; print exists $f[1] ? "e" : "n", exists $f[4] ? "e" : "n", "\n";},
    q{my @g = (1, 2); $#g = 3; push @g, 9; print scalar(@g), exists $g[3] ? "e" : "n", exists $g[4] ? "e" : "n", "\n";},
    # A TIED ARRAY answers through its class (the container's metaobject).
    q{package TA; sub TIEARRAY { my $c = shift; $TA::n = 3; bless {}, $c } sub FETCHSIZE { $main::L .= "Z"; $TA::n } sub FETCH { my ($s, $i) = @_; "e$i" } sub EXISTS { my ($s, $i) = @_; $main::L .= "E$i"; $i < 2 } sub STORESIZE { my ($s, $n) = @_; $main::L .= "S$n"; $TA::n = $n; 1 } package main; my @t; tie @t, "TA"; print exists $t[1] ? "e" : "n", exists $t[-1] ? "e" : "n"; $#t = 0; print " ", scalar(@t), " $main::L\n";},
) {
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $src or diag $r->{why} // explain $r;
}

done_testing;
