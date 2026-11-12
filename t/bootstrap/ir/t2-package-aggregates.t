# ABOUTME: A package array or hash through T2 is a global holding the one
# ABOUTME: aggregate: read where any sub reads it, a whole store refills it in place.
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
    q{our @a = (1, 2); print "@a\n";},
    q{our @a = (1, 2); sub n { scalar @a } print n(), "\n";},
    q{our @a = (1, 2); push @a, 3; print "@a\n";},
    q{our @a = (1); $a[0] = 5; print "@a\n";},
    q{our @a = (1); @a = (5, 6); print "@a\n";},
    q{our @a = (1); sub g { @a = (5); return } g(); print "@a\n";},
    q{our @a = (1); my $r = \@a; @a = (7); print "@$r\n";},
    q{our %h = (k => 1); print $h{k}, "\n";},
    q{our %h = (k => 1); sub g { $h{k} } print g(), "\n";},
    q{our %h = (k => 1); $h{k}++; %h = (j => 2, %h); print join(",", map { "$_=$h{$_}" } sort keys %h), "\n";},
    q{package P; our @L = (3, 4); package main; print "@P::L\n";},
    # A READ IS MADE BEFORE A LATER STORE, here or in a sub called.
    q{our @a = (1); sub g { push @a, 2 } g(); print "@a\n";},
    q{our @a = (1); my $n = scalar(@a); push @a, 2; print "$n @a\n";},
    q{our @a = (1); my $s = "@a"; @a = (4, 5); print "$s @a\n";},
    q{our %h = (a => 1); my $v = $h{a}; %h = (a => 9); print "$v $h{a}\n";},
    q{our @a = (1); my $n = @a; sub g { @a = (2, 3); return } g(); print "$n ", scalar(@a), "\n";},
    q{our @a; for my $i (1..3) { push @a, $i } print "@a\n";},
    q{our %h; $h{$_}++ for qw(a b a); print join(",", map { "$_$h{$_}" } sort keys %h), "\n";},
) {
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $src or diag $r->{why} // explain $r;
}

done_testing;
