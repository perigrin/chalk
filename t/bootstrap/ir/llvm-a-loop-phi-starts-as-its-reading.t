# ABOUTME: A loop-carried value that starts as an Int and becomes a Num starts its
# ABOUTME: phi as that Num: through B::SoN -> chalk -> lli == perl.
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

# `my $s = 0; ... $s = $s + $x / 2` in a loop: the phi is a double, and its
# first value was handed in as the i64 0 -- `phi double [ i64 ... ]`, which
# lli rejected (backlog 22f3248c). The initial value is coerced to the phi's
# reading in the preheader.
for my $case (
    [ q{my $s = 0; for my $x (1 .. 3) { $s = $s + $x / 2 } print "$s\n";}, "3\n", 'an Int accumulator of halves' ],
    [ q{my @a = (1.5, 2); my $s = 0; for my $x (@a) { $s = $s + $x } print "$s\n";}, "3.5\n", 'an Int accumulator over Num elements' ],
    # A Scalar phi starts as a Slot: an undef `my $s` was handed in as its
    # bare defined bit, `phi %Slot [ i1 ... ]` (pvm corpus case 106).
    [ q{sub f { my $s; for my $x (@_) { $s = $x } return $s } print f(3, 4, 5), "\n";}, "5\n", 'an undef that becomes a Scalar' ],
    # ...and its back-edge too: the counter an i64 into a %Slot phi.
    [ q{my $s; for my $x (1 .. 3) { $s = $x } print "$s\n";}, "3\n", 'an undef that becomes the counter' ],
    [ q{my $s = "a"; for my $x (1 .. 2) { $s = $x } print "$s\n";}, "2\n", 'a Str that becomes the counter' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
