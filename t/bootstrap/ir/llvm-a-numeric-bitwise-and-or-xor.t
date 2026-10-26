# ABOUTME: & | ^ when perl does them on numbers (the bitwise feature says so, or an operand
# ABOUTME: is a number written as one); string bitwise is refused: B::SoN -> chalk -> lli == perl.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
sub through_llvm ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# Not lowered at all (pvm 046 051). Perl's & is numeric when an operand has a
# number in it -- a literal does -- or under the bitwise feature; on two
# strings it ANDs their bytes.
for my $c (
    [ q{my $a = $ENV{NOPE} // 12; print $a & 10, " ", $a | 3, " ", $a ^ 3, "\n";} ],
    [ q{use v5.28; my $s1 = $ENV{X1} // "12"; my $s2 = $ENV{X2} // "10"; print $s1 & $s2, "\n";} ],
    [ q{my $x = -6; print $x & 10, " ", 7 ^ 7, " ", 1 | 4, "\n";} ],
    [ q{my $n = 0; for my $i (1 .. 8) { $n++ if $i & 1 } print "$n\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# WHERE PERL MAY DO IT ON BYTES -- two strings and no feature, a ~ on what may
# be a string -- or the answer is past what an integer holds (perl's is
# unsigned): perl's answer, or refused by name. Never another number.
for my $src (
    q{my $s1 = $ENV{X1} // "12"; my $s2 = $ENV{X2} // "10"; print $s1 & $s2, "\n";},
    q{my $a = $ENV{NOPE} // 12; print ~$a & 255, "\n";},
) {
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, qx($^X -e '$src'), "perl's answer: $src") }
    else { like($@, qr/GAP:/, "refused by name: $src") }
}

# PAST AN i64: perl's result is unsigned (18446744073709551615 for -1 & -1),
# which an Int cannot hold. Where no operand proves it small the program
# stops (exit 255) rather than print a negative number.
{
    my $src = q{my $x = -1; print $x & -1, "\n";};
    my $got = eval { through_llvm($src) };
    ok(!defined $got && $@ =~ /GAP:|lli exited 255/, "stopped, not another number: $src") or diag $got // $@;
}

done_testing;
