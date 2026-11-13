# ABOUTME: A loop with no test at its head -- `while (1) { ... next if C; ... last }`,
# ABOUTME: a bare block's `redo` (Carp) -- leaves and goes round from its body, as perl.
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
    q{my $i = $ENV{I} // 0; while (1) { $i++; next if $i < 3; last } print "$i\n";},
    q{my $i = $ENV{I} // 0; while (1) { $i++; if ($i < 3) { next } last } print "$i\n";},
    q{my $i = $ENV{I} // 0; { $i++; redo if $i < 3; } print "$i\n";},
    q{my $i = $ENV{I} // 0; { $i++; redo if $i < 3; $i += 10; redo if $i < 15; } print "$i\n";},
    q{my $i = $ENV{I} // 0; { $i++; if ($i > 4) { last } redo; } print "$i\n";},
    q{my ($i, $n) = ($ENV{I} // 1, 0); { my $c = $i; $i++; $n++; redo if $c < 3; } print "$i $n\n";},
    q{sub f { my $i = shift; { $i++; return $i * 10 if $i > 2; last if $i > 99; redo; } return -1 } print f($ENV{I} // 0), "\n";},
    # Carp's short_error_loc, its shape: redo on each condition, return, the end.
    q{our %I = (b => 1); my @c = ("a", "b", "b", "c", "d"); sub loc { my $i = $ENV{I} // 0; my $lvl = 1; { my $x = $c[$i]; $i++; return 0 unless defined $x; redo if $I{$x}; redo unless 0 > --$lvl; } return $i - 1 } print loc(), "\n";},
    q{my @l; my $i = $ENV{I} // 0; { push @l, $i++; redo if $i < 4; } print "@l\n";},
) {
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $src or diag $r->{why} // explain $r;
}

done_testing;
