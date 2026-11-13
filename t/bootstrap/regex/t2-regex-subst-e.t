# ABOUTME: s///ge through T2: the replacement body runs once per match, in order,
# ABOUTME: reading that match's $& and $1.. (undef where a group took no part).
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
    q{my $s = $ENV{S} // "a1b2"; $s =~ s/(\d)/$1*2/ge; print "$s\n";},
    q{my $s = $ENV{S} // "a1b22"; my $n = ($s =~ s/(\d+)/$1+1/ge); print "$n $s\n";},
    q{my $s = $ENV{S} // "abzb"; $s =~ s/(b)|(z)/defined $2 ? "Z" : uc $1/ge; print "$s\n";},
    q{our @C = ("p", "q"); my $s = $ENV{S} // "XXaX"; $s =~ s/X/$C[ int( rand( @C ) ) ]/ge; print length($s), " ", ($s =~ tr/pq//), "\n";},
    q{our @C = ("p", "q"); my $s = $ENV{S} // "XaX"; $s =~ s/X/$C[1]/ge; print "$s\n";},
    q{my $s = $ENV{S} // "none"; $s =~ s/(\d)/$1*2/ge; print "$s\n";},
    # AN INTERPOLATED PATTERN of a few constants: a matcher for each, one picked
    # (File::Temp's _replace_XX).
    q{our @C = ("p", "q"); my $end = ( $] >= 5.006 ? "\\z" : "\\Z" ); my $p = $ENV{S} // "abXXX"; $p =~ s/X(?=X*$end)/$C[ int( rand( @C ) ) ]/ge; print length($p), " ", ($p =~ tr/pq//), "\n";},
    q{my $end = ( $ENV{Z} ? "b" : "c" ); my $p = $ENV{S} // "aXbXc"; $p =~ s/X(?=$end)/Y/g; print "$p\n";},
    q{print "$]\n"; print $] >= 5.006 ? "new\n" : "old\n";},
) {
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $src or diag $r->{why} // explain $r;
}

# A PATTERN MADE AT RUN TIME of what is not a few constants: refused, never a
# wrong match.
for my $src (
    q{my $d = $ENV{D} // "1"; my $s = "a1b2"; $s =~ s/($d)/<$1>/ge; print "$s\n";},
    q{my $d = $ENV{D} // "1"; my $s = "a1b2"; $s =~ s/$d/Q/g; print "$s\n";},
) {
    my $r = tap("$src\n");
    isnt $r->{verdict}, 'DIFFERS', "no wrong match: $src" or diag $r->{why};
}

done_testing;
