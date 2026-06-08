# ABOUTME: Runner for the increment mdtest corpus topic (constructive format).
# ABOUTME: Exercises K1 (pre-increment) and K2 (post-increment) — both GREEN with Assign write-back.
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
# SECTION 1: Parse increment.md and verify case inventory
#
# K1 (pre-increment) and K2 (post-increment) must both be present.
# Both declare L: GREEN: the Assign write-back + distinct PadAccess nodes
# produce a lowerable graph that lli agrees with perl (returns 1).
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($INCREMENT_MD);
is(scalar(@$cases), 2, 'increment.md has 2 cases (K1 and K2)');

my @titles = map { $_->{title} } @$cases;
ok((grep { /K1.*pre.?increment/i  } @titles), 'case: K1 pre-increment present');
ok((grep { /K2.*post.?increment/i } @titles), 'case: K2 post-increment present');

# ---------------------------------------------------------------------------
# SECTION 2: Run both cases end-to-end
#
# For each case:
#   - behavior check PASS (perl oracle: $i returns 1 after increment from 0)
#   - ir-shape check not FAIL (graph builds and passes TypedInvariant)
#   - L-verdict check PASS (declared GREEN matches actual GREEN from LLVMDriver)
#   - lli output == perl oracle (1)
# ---------------------------------------------------------------------------

for my $case (@$cases) {
    my $title = $case->{title};

    subtest "case: $title" => sub {
        my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {});

        # Behavior: perl says $i == 1 after increment from 0
        is($result->{behavior}{verdict}, 'PASS',
            "$title: behavior oracle matches")
            or diag("  behavior fail: " . join('; ', @{ $result->{fail_reasons} }));

        # IR-shape: built graph must pass TypedInvariant
        isnt($result->{ir_shape}{verdict}, 'FAIL',
            "$title: ir-shape not FAIL")
            or diag("  ir-shape fail: " . join('; ', @{ $result->{fail_reasons} }));

        # L-verdict: declared GREEN must match actual GREEN
        is($result->{l_verdict}{verdict}, 'PASS',
            "$title: L verdict matches GREEN")
            or diag("  L fail: " . join('; ', @{ $result->{fail_reasons} }));

        # Overall
        is($result->{overall}, 'PASS', "$title: overall PASS")
            or diag("  fail reasons: " . join('; ', @{ $result->{fail_reasons} }));

        # Direct proof: build graph from ir block -> lli -> 1 == perl
        my $decl_verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir(
            $case->{ir} // '');
        is($decl_verdict, 'GREEN', "$title: ir block declares L: GREEN");

        my $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir(
            $case->{ir});
        ok(defined $return_node, "$title: build_graph_from_ir returns a node");

        if (defined $return_node) {
            my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
            ok(!$meta->{marked_unsupported},
                "$title: built-from-block graph is truly GREEN (not marked_unsupported)");
            my $lli_out  = $L->return_values->[0] // '';
            my $perl_out = $case->{_perl_actual}  // '';
            is($lli_out, 'Int:1', "$title: lli output is Int:1 (type-tagged)");
            is($perl_out, 'Int:1', "$title: perl oracle is Int:1 (type-tagged)");
            is($lli_out, $perl_out, "$title: lli output == perl oracle (both Int:1)");
        }
    };
}

# ---------------------------------------------------------------------------
# SECTION 3: Both K1 and K2 declare L: GREEN
#
# Unlike the control-flow topic (all GAP), both increment cases are GREEN.
# The Assign write-back + distinct PadAccess nodes give the LLVM target
# enough information to lower runtime-free.
# ---------------------------------------------------------------------------

subtest 'both K1 and K2 declare L: GREEN' => sub {
    plan tests => 2;
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
        is($L->return_values->[0], 'Int:1',
            'K1 lli output is Int:1 (B1 guard did not fire; no stale-read GAP, type-tagged)');
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
