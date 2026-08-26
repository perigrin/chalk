# ABOUTME: Mode2Adapter must NEVER pass program_mode: its oracle EATS the epilogue.
# ABOUTME: Makes the omission load-bearing -- a "helpful" unifier adding it fails here.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib', 't/lib';
use Chalk::CodeGen::Pipeline;
use Chalk::CodeGen::Harness::Mode2Adapter;
use Chalk::CodeGen::Harness::TypeTag;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI"        unless -x $LLI;
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;

# ---------------------------------------------------------------------------
# WHY THIS TEST EXISTS
#
# Four of the five end-to-end assemblers were unified onto one Pipeline. Two of
# them pass `program_mode => 1`, which SUPPRESSES the Int:/Str: return-value
# epilogue. Mode2Adapter is one of the three that must NOT: its behavior oracle
# is _tag_expected, which turns a harvested plain literal (4) into the TAGGED
# face lli prints (`Int:4`) and compares them. With program_mode on, lli prints
# no tag, every comparison fails, and the conformance tally silently reads 0.
#
# A code comment cannot fail a build. This test can. It asserts BOTH halves --
# that the flag is absent AND that the oracle it protects still works -- so the
# omission is self-documenting rather than a fact someone has to already know.
# ---------------------------------------------------------------------------

my @cases = (
    { subject => '2 + 2',  expected => 4,   cmp => 'eq', file => 'synthetic', line => 1 },
    { subject => '"-"',    expected => '-', cmp => 'eq', file => 'synthetic', line => 2 },
);

# --- (a) the invocation does NOT pass program_mode -------------------------
# Observed at runtime, not grepped: wrap the seam and record every %opts the
# adapter actually hands it. A future unifier that adds the flag -- in the
# adapter, in a shared default, or in Pipeline's own constructor -- trips this.
my @seen_opts;
{
    no warnings 'redefine';
    my $real = Chalk::CodeGen::Pipeline->can('run_detail');
    *Chalk::CodeGen::Pipeline::run_detail = sub {
        my ($self, $json, $select, %opts) = @_;
        push @seen_opts, \%opts;
        return $real->($self, $json, $select, %opts);
    };
    my $real_run = Chalk::CodeGen::Pipeline->can('run');
    *Chalk::CodeGen::Pipeline::run = sub {
        my ($self, $json, $select, %opts) = @_;
        push @seen_opts, \%opts;
        return $real_run->($self, $json, $select, %opts);
    };
}

my $result = Chalk::CodeGen::Harness::Mode2Adapter->run_cases(\@cases);

cmp_ok(scalar @seen_opts, '>=', 1,
       'Mode2Adapter reached the Pipeline seam (the observation is not vacuous)');
for my $i (0 .. $#seen_opts) {
    ok(!exists $seen_opts[$i]{program_mode},
       "invocation $i does NOT pass program_mode (the epilogue must survive)");
}

# --- (b) the oracle it protects still works --------------------------------
# The type-tagged expectations must MATCH. If program_mode ever leaks in, the
# lli output loses its `Int:`/`Str:` prefix and these comparisons go red -- so
# this half is the reason (a) is a requirement rather than a preference.
my $c = $result->{conformance};
is($c->{total}, 2, 'both cases ran');
is($c->{pass},  2, 'both type-tagged expectations still match (the oracle works)');
is($c->{pct}, 100, 'conformance is 100%');

for my $v ($result->{cases}->@*) {
    ok($v->{behavior_ok}, "case '$v->{subject}' behavior leg passed");
    like($v->{lli}, qr/^(?:Int|Str|Num|Bool|Undef):/,
         "case '$v->{subject}' lli output CARRIES a type tag -- the epilogue was emitted");
    is($v->{lli}, Chalk::CodeGen::Harness::TypeTag::infer_tag($v->{expected}),
       "case '$v->{subject}' lli output equals the tagged harvested expected");
}

done_testing();
