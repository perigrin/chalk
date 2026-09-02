# ABOUTME: I11 tri-fold adapter test — harvested Mode-2 cases run behavior+invariant
# ABOUTME: under a SEPARATE conformance tally that never touches hand corpus gate-green.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib', 't/lib';
use Chalk::CodeGen::Harness::Mode2Adapter;
use Chalk::CodeGen::Harness::Mode2Extractor;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI"        unless -x $LLI;
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;

# ---------------------------------------------------------------------------
# Two harvested cases. The harvested EXPECTED is the oracle (Perl's t/ already
# told us the answer) — the adapter must NOT re-run perl; it wraps the lowered
# graph so the value is PRINTED (bracketed) and compares that. Shape-leg contract C:
# harvested cases run BEHAVIOR + INVARIANT only (no hand-corpus ir block).
#   * '2 + 2'  -> 4     — a self-contained arithmetic case that lowers GREEN.
#   * '"-"'    -> '-'   — the shape a real harvest from opbasic/concat.t produces.
# ---------------------------------------------------------------------------
my @cases = (
    { subject => '2 + 2',  expected => 4,   cmp => 'eq', file => 'synthetic', line => 1 },
    { subject => '"-"',    expected => '-', cmp => 'eq', file => 'synthetic', line => 2 },
);

my $result = Chalk::CodeGen::Harness::Mode2Adapter->run_cases(\@cases);

# --- A SEPARATE harvested-conformance tally is reported --------------------
ok(exists $result->{conformance}, 'run_cases reports a conformance tally');
my $c = $result->{conformance};
is($c->{total}, 2, 'conformance total counts all harvestable cases');
ok(exists $c->{pass}, 'conformance carries a pass count');
ok(exists $c->{pct},  'conformance carries a pct');
cmp_ok($c->{pass}, '<=', $c->{total}, 'pass never exceeds total');

# Both self-contained cases lower to their harvested expected value.
is($c->{pass}, 2, 'both harvested cases conform (behavior == harvested expected)');
is($c->{pct}, 100, 'conformance pct is pass/total * 100');

# --- Per-case behavior + invariant legs ran (contract C: no shape leg) -----
ok(exists $result->{cases}, 'per-case verdicts are reported');
is(scalar $result->{cases}->@*, 2, 'one verdict per case');
for my $v ($result->{cases}->@*) {
    ok(exists $v->{behavior_ok},  "case reports a behavior leg");
    ok(exists $v->{invariant_ok}, "case reports an invariant leg");
    ok(!exists $v->{shape_ok},    "contract C: harvested case has NO shape leg");
}

# --- HONEST-NUMBER DISCIPLINE (R6.1): the two tallies are never conflated ---
# Running harvested cases must NOT change the hand corpus gate-green number.
# We prove it directly: capture the hand gate BEFORE and AFTER running harvested
# cases in the same process; the hand number is a property of the hand corpus
# alone and the adapter is forbidden from mutating it.
my $hand_before = hand_gate_green();
Chalk::CodeGen::Harness::Mode2Adapter->run_cases(\@cases);
my $hand_after = hand_gate_green();
is($hand_before, $hand_after,
   'harvested conformance run does NOT change hand gate-green (tallies never conflated)');
# The hand gate-green number is a real, non-zero property of the hand corpus that
# rises as the hand corpus grows — assert it is present and plausible, NOT a
# frozen literal (a hardcoded value goes stale the moment any later issue raises
# the gate; the invariant is that the harvested run does not TOUCH it, proved
# above, not that it equals a specific number).
cmp_ok($hand_before, '>', 0, 'hand gate-green baseline is a real non-zero number (unchanged by harvested tally)');
isnt($c->{pass}, $hand_before,
     'the harvested-conformance number is a DIFFERENT number than hand gate-green');

# --- Promotion path: a gap-revealing case emits a hand-corpus-shaped record --
# A case that lowers wrong / GAPs is a candidate for PROMOTION into the hand
# corpus WITH an ir block (full tri-fold). We exercise the promotion path on a
# deliberately gap-revealing case (an out-of-subset subject the backend cannot
# lower). The promote() path emits a hand-corpus record record so a human can
# add the ir block and certify it as a full tri-fold case.
my $gap_case = { subject => 'sprintf("%d", 3)', expected => 3, cmp => 'eq',
                 file => 'synthetic', line => 3 };
my $promo = Chalk::CodeGen::Harness::Mode2Adapter->promote($gap_case);
ok(defined $promo, 'promote() emits a record for a gap-revealing case');
is($promo->{source}, 'sprintf("%d", 3)', 'promotion record carries the subject as source');
like($promo->{behavior}, qr/return:\s*3/, 'promotion record carries the harvested expected as behavior return');
like($promo->{ir}, qr/L:\s*GAP/, 'promotion record ir block is stamped L: GAP (needs human ir + re-cert)');
ok(exists $result->{promotions}, 'run_cases reports a promotions list');

# ---------------------------------------------------------------------------
# hand_gate_green(): re-run the hand corpus gate the same way son-corpus-wide.t
# does and return the gate-green count. This is the load-bearing proof that the
# harvested tally is SEPARATE — it re-measures the hand corpus independently.
# ---------------------------------------------------------------------------
sub hand_gate_green {
    my $out = qx($PERL -Ilib -It/lib t/bootstrap/corpus/son-corpus-wide.t 2>&1);
    return $1 if $out =~ /gate-green=(\d+)/;
    return -1;
}

done_testing();
