# ABOUTME: A loop on wire v2's `loop` profile: Loop [entry, back], its test an If on the Loop (or
# ABOUTME: on the condition's last effect), Proj 0 the body; T2 lowers it to perl's output.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
require Chalk::CodeGen::Pipeline;

# lower($json) -> (ll or undef, why), through T2 alone
sub lower ($json) {
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = $units->[0] // {};
    my $ll = !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef;
    return ($ll, $err // $u->{path_why} // $u->{err});
}

sub runs ($file, $want, $what) {
    my $json = do { local (@ARGV, $/) = $file; <> };
    my ($ll, $why) = lower($json);
    ok(defined $ll, "$what: lowered through T2") or diag $why;
    SKIP: {
        skip 'not lowered', 1 unless defined $ll;
        my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        print $lf $ll; close $lf;
        is(qx(timeout 20 $LLI $llp 2>&1), $want, "$what: perl's output");
    }
}

# THE WIRE OF docs/plans/2026-11-20-wire-v2.md, section 3.6, written by hand
# (ids renumbered to positions):
#
#     our $g = 0; my $i = 0; while ($i < 3) { $g = $g + $i; $i++ } print "$g\n";
#
# Loop#6 [5, 17]: its back input is the body's last control, a forward
# reference like a loop Phi's. The test is If#11 [6, 10]; NumLt#10 is an
# ordinary value. Proj 0 of the If is the body, Proj 1 the way out. The read
# after the loop names the header memory Phi.
runs('t/data/wire-v2-loop-if-back-edge.json', "3\n", 'the 3.6 loop');

# A TEST WITH AN EFFECT: `my @w = (1, 2); while (my $n = shift @w) { print $n }`.
# The shift is pinned on the Loop, the If on the shift: the effect runs each
# pass before the test, and the way out leaves after it (Return#17 names it).
runs('t/data/wire-v2-loop-test-effect.json', "12", 'a test with an effect');

done_testing;
