# ABOUTME: A sub with several early returns returns each one: its merges nest, and
# ABOUTME: an inner merge's phi is an outer arm's value -- B::SoN -> chalk -> lli == perl.
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

# A MERGE INSIDE AN ARM IS THAT ARM'S VALUE. `return A if C1; return B if
# C2; return D` merges two at a time on the wire: the inner If's two arms,
# then that merge and the outer If's other arm. The inner merge's phi is an
# arm of the outer one, lowered with the arm, where its If has run -- and it
# was refused as "made inside one of its arms" (pvm subroutines.md).
for my $case (
    [ q{sub c { return "z" if $_[0] == 0; return "n" if $_[0] < 0; return "p" } print c(0), c(-5), c(7), "\n";}, "znp\n", 'three exits' ],
    [ q{sub c { my $n = shift; if ($n > 5) { return "big" } return "zero" if $n == 0; print "mid\n"; return "small" } print c(9), c(0), c(3), "\n";}, "mid\nbigzerosmall\n", 'an effect before the last exit' ],
    [ q{sub f { if ($_[0]) { if ($_[0] > 1) { return "a" } else { return "b" } } else { return "c" } } print f(2), f(1), f(0), "\n";}, "abc\n", 'nested if/else' ],
    [ q{sub g { my $x = shift; if ($x > 1) { if ($x > 2) { print "p\n"; return 3 } return 2 } return 1 } print g(3), g(2), g(0), "\n";}, "p\n321\n", 'a nested guard that prints' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
