# ABOUTME: A range where neither bound is a number (`$s[0] .. "bb"`): perl's choice at run
# ABOUTME: time -- on numbers where the strings look like them, else magic increment.
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
    [ q{my @seed = ("az"); my @r = ($seed[0] .. "bb"); print "@r ", scalar(@r), "\n";}, 'pvm range:2' ],
    [ q{my @s = ("a9", "zz", "Zz", "09", "x", "aaa", "", "a-b");
        print join(",", $s[0] .. "b2"), "|", join(",", $s[1] .. "aab"), "|", join(",", $s[2] .. "AAc"), "|", join(",", $s[3] .. "12"), "\n";
        print join(",", $s[4] .. "y"), "|", join(",", $s[5] .. "b"), "|", scalar(() = ($s[6] .. "c")), "|", join(",", $s[7] .. "zzz"), "\n";}, 'magic increments, and where they stop' ],
    [ q{my @n = ("2", "11", " 1", "1.5", "a"); print join(",", $n[0] .. $n[1]), "|", join(",", $n[2] .. "3"), "|", join(",", $n[3] .. "4"), "|", join(",", $n[4] .. "5"), "\n";}, 'strings that look like numbers' ],
    [ q{my @s = ("a"); my @r = ($s[0] .. "zz"); print scalar(@r), " $r[-1]\n";}, 'a .. zz' ],
    # (each literal its own: B::SoN's one node for two would be read by two
    # ranges, and a range on numbers makes its bound a number)
) {
    my $r = tap("$case->[0]\n");
    is $r->{verdict}, 'SAME', $case->[1] or diag $r->{why} // explain $r;
}

# A BOUND A NUMERIC READ MAY HAVE MADE A NUMBER (perl's range is then on
# numbers): refused by name.
{
    my $r = tap(qq{my \@s = ("az"); my \$x = \$s[0] + 0; my \@r = (\$s[0] .. "bb"); print "\@r \$x\\n";\n});
    is $r->{verdict}, 'REFUSED', 'a bound read as a number elsewhere';
    like $r->{why} // '', qr/a range of strings a numeric read may have made numbers/, 'by name';
    # (a range on numbers makes its bounds numbers: $s[-2] is $s[0])
    $r = tap(qq{my \@s = ("5", "q"); my \@a = (\$s[0] .. "7"); my \@b = (\$s[-2] .. "z"); print "\@a|\@b\n";\n});
    is $r->{verdict}, 'REFUSED', 'an element a range on numbers read, by another index';
}

done_testing;
