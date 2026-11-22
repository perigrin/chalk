# ABOUTME: A block eval on wire v2's `eval` profile: the die's exceptional edge (Exc) carries the
# ABOUTME: `local`'s restore to a catch Region, where $@ is stored; T2 lowers it to perl's output.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
require Chalk::CodeGen::Pipeline;

# THE WIRE OF docs/plans/2026-11-20-wire-v2.md, section 3.5, written by hand:
#
#     our $g = 1; eval { local $g = 2; die "x\n" }; print "$g $@";
#
# perl prints `1 x`. On the `mem` profile alone the join took the local's
# store through the Unwind (no restore, no $@ store): `2 x`, refused by
# WireCheck. Here the Unwind's way out is an Exc, the restore stands on it
# (node 15 puts back node 10, $g read before the local), the catch Region
# (16) merges the edge, $@ is stored from the Exc (18), and the join (19)
# has the one way in: the body always dies.
# (the wire: t/data/wire-v2-eval-catch-edge.json)
my $json = do { local (@ARGV, $/) = 't/data/wire-v2-eval-catch-edge.json'; <> };

# lower($json) -> (ll or undef, why), through T2 alone
sub lower ($json) {
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = $units->[0] // {};
    my $ll = !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef;
    return ($ll, $err // $u->{path_why} // $u->{err});
}

my ($ll, $why) = lower($json);
ok(defined $ll, 'the eval with a catch edge is lowered through T2') or diag $why;
SKIP: {
    skip 'not lowered', 1 unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    my $got = qx(timeout 20 $LLI $llp 2>&1);
    is($got, "1 x\n", 'the local is put back on the die\'s way out, and $@ is what the die threw');
}
done_testing;
