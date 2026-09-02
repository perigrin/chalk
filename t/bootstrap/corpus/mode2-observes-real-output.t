# ABOUTME: Mode2Adapter's behavior oracle must read REAL printed program output.
# ABOUTME: Pins the seam is reached and that lli actually printed, not printed nothing.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib', 't/lib';
use Chalk::CodeGen::Pipeline;
use Chalk::CodeGen::Harness::Mode2Adapter;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI"        unless -x $LLI;
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;

# ---------------------------------------------------------------------------
# WHY THIS TEST EXISTS
#
# A lowered graph prints only what its Print nodes print. Mode2Adapter's
# behavior oracle therefore depends on the adapter WRAPPING the case so the
# return value is printed -- and a wrapper that silently prints nothing still
# `lower()`s fine and still runs clean under lli. That failure mode is real: a
# lowering that succeeded and printed an empty string shipped once already.
#
# mode2-adapter.t asserts the aggregate tally. It cannot tell a genuine match
# from two empty strings comparing equal. This test asserts the observation
# itself is real: the seam is reached, and each case's lli output is the
# BRACKETED value, not '' and not undef.
#
# The brackets are the load-bearing part. Without them a case whose value is
# legitimately empty is indistinguishable from a case that printed nothing at
# all -- the exact confusion the empty-string bug hid behind.
# ---------------------------------------------------------------------------

my @cases = (
    { subject => '2 + 2',  expected => 4,   cmp => 'eq', file => 'synthetic', line => 1 },
    { subject => '"-"',    expected => '-', cmp => 'eq', file => 'synthetic', line => 2 },
    # A legitimately EMPTY value. Under a bracket-less oracle this case is
    # indistinguishable from "printed nothing"; under this one it is `[]`.
    { subject => '""',     expected => '',  cmp => 'eq', file => 'synthetic', line => 3 },
);

# --- (a) the adapter actually reaches the Pipeline seam --------------------
# Observed at runtime, not grepped, so the rest of this file cannot pass
# vacuously against an adapter that never lowered anything.
my $seam_hits = 0;
{
    no warnings 'redefine';
    my $real = Chalk::CodeGen::Pipeline->can('run_detail');
    *Chalk::CodeGen::Pipeline::run_detail = sub {
        my ($self, $json, $select, %opts) = @_;
        $seam_hits++;
        return $real->($self, $json, $select, %opts);
    };
}

my $result = Chalk::CodeGen::Harness::Mode2Adapter->run_cases(\@cases);

cmp_ok($seam_hits, '>=', 1,
       'Mode2Adapter reached the Pipeline seam (the observation is not vacuous)');

# --- (b) every case observed a REAL printed value --------------------------
my $c = $result->{conformance};
is($c->{total}, 3, 'all three cases ran');
is($c->{pass},  3, 'all three behavior legs match the harvested expected');
is($c->{pct}, 100, 'conformance is 100%');

for my $v ($result->{cases}->@*) {
    ok($v->{behavior_ok}, "case '$v->{subject}' behavior leg passed");
    ok(defined $v->{lli} && $v->{lli} ne '',
       "case '$v->{subject}' lli PRINTED something (not the empty-output failure)");
    like($v->{lli}, qr/^\[.*\]$/,
         "case '$v->{subject}' lli output is the bracketed printed value");
}

# The empty-valued case is the discriminator: it must print `[]`, which is
# distinguishable from the '' a graph that printed nothing would yield.
my ($empty) = grep { $_->{subject} eq '""' } $result->{cases}->@*;
is($empty->{lli}, '[]',
   'a legitimately empty value prints `[]`, NOT nothing (the brackets discriminate)');

done_testing();
