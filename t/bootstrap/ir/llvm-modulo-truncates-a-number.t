# ABOUTME: perl's % truncates a number operand to an integer first: through
# ABOUTME: B::SoN -> chalk -> lli == perl.
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

# A Num OPERAND REACHED `srem i64` AS A double, and lli rejected the module:
# `%` lowered every operand as an i64 whatever its stamp. perl's % reads an
# integer from each operand -- 7.5 % 2 is 7 % 2, -7.9 % 3 is -7 % 3 -- which
# is fptosi's truncation toward zero.
for my $case (
    [ q{my $x = 7.5; $x = $x + 0; print $x % 2, "\n";}, "1\n", 'a Num dividend' ],
    [ q{my @a = (7.5, 3); print $a[0] % 2, "\n";}, "1\n", 'a Num element' ],
    [ q{my $x = -7.9; $x = $x + 0; print $x % 3, "\n";}, "2\n", 'a negative Num truncates toward zero' ],
    [ q{sub f { my $n = shift; if ($n % 2) { print "o" } else { print "e" } return $n } for my $i (1 .. 4) { f($i) } print "\n";}, "oeoe\n", "an argument read through a Scalar" ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
