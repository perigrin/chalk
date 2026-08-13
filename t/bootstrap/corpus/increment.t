# ABOUTME: Runner for the increment mdtest corpus topic (constructive format).
# ABOUTME: Asserts the topic's static inventory + L declarations; behavior/shape/invariant is owned by son-corpus-wide.t.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness::MdtestCorpus;
use Chalk::CodeGen::Harness::LLVMDriver;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

my $INCREMENT_MD = 't/corpus/mdtest/increment.md';

unless (-f $INCREMENT_MD) {
    plan skip_all => "increment.md not found at $INCREMENT_MD";
}

# ---------------------------------------------------------------------------
# SECTION 1: Parse increment.md and verify the topic's named idioms are present.
#
# K1 (pre-increment) and K2 (post-increment) must both be present. This runner
# asserts the STATIC inventory + L declarations of the corpus file. The
# authoritative behavior/shape/invariant gate is
# t/bootstrap/corpus/son-corpus-wide.t, which lowers each case's PERL SOURCE
# through B::SoN -> chalk -> lli. The old per-case run_case checks here lowered
# the hand-written IR BLOCK through the constructive builder -- a second,
# drifting lowering path with hardcoded case counts that went stale on every
# corpus addition (zhi 019f53a0). Retired in favor of the single authoritative
# gate; the presence/declaration checks below lower nothing and stay.
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($INCREMENT_MD);

my @titles = map { $_->{title} } @$cases;
ok((grep { /K1.*pre.?increment/i  } @titles), 'case: K1 pre-increment present');
ok((grep { /K2.*post.?increment/i } @titles), 'case: K2 post-increment present');

# ---------------------------------------------------------------------------
# SECTION 3: Both K1 and K2 declare L: GREEN
#
# Unlike the control-flow topic (all GAP), both increment cases are GREEN.
# The Assign write-back + distinct PadAccess nodes give the LLVM target
# enough information to lower runtime-free.
# ---------------------------------------------------------------------------

subtest 'both K1 and K2 declare L: GREEN' => sub {
    plan tests => scalar @$cases;
    for my $case (@$cases) {
        my $ir_text = $case->{ir} // '';
        my $decl = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        is($decl, 'GREEN',
            "case '$case->{title}': declared L: GREEN");
    }
};

# ---------------------------------------------------------------------------
# SECTION 4: Distinct PadAccess nodes prevent the B1 stale-read guard
#
# The RMW read ($i_r), the lhs slot ($i_l), and the final return read ($i)
# use different varnames — they hash-cons to DIFFERENT PadAccess nodes.
# This means no aliasing occurs and the B1 poison guard never fires.
# Verify by checking that the built graph produces no GAP result from lli.
# ---------------------------------------------------------------------------

subtest 'distinct PadAccess varnames prevent B1 stale-read GAP' => sub {
    my ($k1_case) = grep { $_->{title} =~ /K1/i } @$cases;
    ok(defined $k1_case, 'K1 case found for B1-guard check');

    my $return_node;
    eval {
        $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir(
            $k1_case->{ir});
    };
    ok(!$@, "K1 graph builds without error: $@");
    ok(defined $return_node, 'K1 build_graph_from_ir returns a node');

    if (defined $return_node) {
        my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
        ok(!$meta->{marked_unsupported},
            'K1 graph lowers without triggering B1 stale-read GAP');
        is($L->return_values->[0], '1',
            'K1 lli prints 1 (B1 guard did not fire; no stale-read GAP)');
    }
};

# ---------------------------------------------------------------------------
# SECTION 5: Negative guard — claiming L: GREEN for a GAP idiom FAILS
#
# We reuse the same guard as arithmetic/control-flow: a Scalar-repr constant
# that cannot lower runtime-free, claiming GREEN, must FAIL.
# ---------------------------------------------------------------------------

subtest 'guard: L: GREEN for a real GAP FAILS' => sub {
    use File::Temp qw(tempfile);
    my $fake_green_md = <<'END_MD';
# Fake

## Fake GREEN increment case

```perl
# source
my $i = 0; $i++; $i
```

```behavior
return: 1
context: scalar
```

```ir
%c0 = Constant(0) :Scalar
return %c0
L: GREEN
```
END_MD

    my ($fh, $tmpfile) = tempfile(SUFFIX => '.md', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $fake_green_md;
    close $fh;

    my $fake_cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($tmpfile);
    my $fake_case  = $fake_cases->[0];
    my $result     = Chalk::CodeGen::Harness::MdtestCorpus->run_case($fake_case, {});

    is($result->{l_verdict}{verdict}, 'FAIL',
        'L verdict FAILS when actual is GAP but declared GREEN');
    is($result->{overall}, 'FAIL', 'overall is FAIL');
    like($result->{fail_reasons}[0] // '', qr/L verdict|GAP|GREEN/i,
        'fail reason mentions L verdict, GAP, or GREEN');
};

done_testing;
