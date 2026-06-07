# ABOUTME: Runner for the control-flow mdtest corpus topic (constructive format).
# ABOUTME: Exercises D1-D8 control-flow idioms: D6 is a builder GAP (TernaryExpr 3-input); D1-D5/D7/D8 are LLVM GAPs.
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

my $CONTROL_FLOW_MD = 't/corpus/mdtest/control-flow.md';

unless (-f $CONTROL_FLOW_MD) {
    plan skip_all => "control-flow.md not found at $CONTROL_FLOW_MD";
}

# ---------------------------------------------------------------------------
# SECTION 1: Parse control-flow.md and verify case inventory
#
# All 8 control-flow idioms (D1-D8) must be present.  D6 is a builder GAP
# (TernaryExpr requires 3 inputs; the binary-op pattern handles 2 args only).
# D1-D5, D7, D8 are LLVM GAPs (br + phi or landingpad not yet lowerable).
# The corpus MUST record these GAPs honestly — a GREEN claim for any of them
# would be a lie and must fail.
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($CONTROL_FLOW_MD);
is(scalar(@$cases), 8, 'control-flow.md has 8 cases (D1-D8)');

my @titles = map { $_->{title} } @$cases;
ok((grep { /D6.*ternary/i } @titles),    'case: D6 ternary present');
ok((grep { /D1.*if.*else/i } @titles),   'case: D1 if/else present');
ok((grep { /D2.*while/i }   @titles),    'case: D2 while present');
ok((grep { /D3.*foreach/i } @titles),    'case: D3 foreach present');
ok((grep { /D4.*postfix.*if/i } @titles),'case: D4 postfix if present');
ok((grep { /D5.*postfix.*while/i } @titles), 'case: D5 postfix while present');
ok((grep { /D7.*nested/i }  @titles),    'case: D7 nested if present');
ok((grep { /D8.*try/i }     @titles),    'case: D8 try/catch present');

# ---------------------------------------------------------------------------
# SECTION 2: Run all 8 cases end-to-end
#
# For each case:
#   - behavior check must PASS (perl oracle vs declared return value)
#   - ir-shape check must not FAIL (pure-GAP blocks trivially pass)
#   - L-verdict check must PASS (declared GAP matches actual GAP)
#
# The CRITICAL assertion: ALL 8 cases declare L: GAP.
# D6 is a builder GAP (not an LLVM-lowering GAP — the LLVM backend supports
# TernaryExpr — but the markdown builder cannot construct a 3-input node from
# the current named-SSA syntax, so the ir block is correctly written as pure-GAP).
# D1-D5/D7/D8 are genuine LLVM GAPs (no basic-block lowering).
# ---------------------------------------------------------------------------

for my $case (@$cases) {
    my $title = $case->{title};

    subtest "case: $title" => sub {
        my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {});

        # Behavior check: perl oracle must agree with declared return
        is($result->{behavior}{verdict}, 'PASS',
            "$title: behavior oracle matches")
            or diag("  behavior fail: " . join('; ', @{ $result->{fail_reasons} }));

        # IR-shape check: pure-GAP blocks trivially pass (no graph to validate)
        isnt($result->{ir_shape}{verdict}, 'FAIL',
            "$title: ir-shape not FAIL")
            or diag("  ir-shape fail: " . join('; ', @{ $result->{fail_reasons} }));

        # L-verdict check: declared GAP must match actual GAP
        is($result->{l_verdict}{verdict}, 'PASS',
            "$title: L verdict matches")
            or diag("  L fail: " . join('; ', @{ $result->{fail_reasons} }));

        # Overall
        is($result->{overall}, 'PASS', "$title: overall PASS")
            or diag("  fail reasons: " . join('; ', @{ $result->{fail_reasons} }));
    };
}

# ---------------------------------------------------------------------------
# SECTION 3: Verify ALL cases declare L: GAP (none claim GREEN)
#
# A control-flow case claiming GREEN when the LLVM backend cannot lower it
# would be dishonest.  D6 specifically: the LLVM _lower_ternary exists but
# the builder has no 3-input form — the correct answer is to GAP the ir
# block, not to hand-wave a GREEN.  If the builder gains a 3-input form in
# the future, this guard must be removed for D6 only at that time.
# ---------------------------------------------------------------------------

subtest 'all 8 control-flow cases declare L: GAP (none claim GREEN)' => sub {
    plan tests => 8;
    for my $case (@$cases) {
        my $ir_text = $case->{ir} // '';
        my $decl = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        is($decl, 'GAP',
            "case '$case->{title}': declared L: GAP (not GREEN)");
    }
};

# ---------------------------------------------------------------------------
# SECTION 4: Builder gap audit for D6
#
# Verify that build_graph_from_ir correctly handles the pure-GAP block for D6
# (returns undef, does not croak) — the block has no node lines, only L: GAP.
# This confirms the corpus format is correct even for the builder-gap case.
# ---------------------------------------------------------------------------

subtest 'D6 pure-GAP block: build_graph_from_ir returns undef (no nodes to build)' => sub {
    my ($d6_case) = grep { $_->{title} =~ /D6.*ternary/i } @$cases;
    ok(defined $d6_case, 'D6 case found');

    my $ir_text = $d6_case->{ir} // '';

    # The D6 ir block is pure-GAP (only an L: GAP line, no %name = ... lines)
    my $return_node;
    eval {
        $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text);
    };
    ok(!$@, "D6 build_graph_from_ir does not croak (got: $@)")
        or diag("build error: $@");
    ok(!defined $return_node,
        'D6 build_graph_from_ir returns undef for pure-GAP block');

    # The L verdict must be GAP
    my $verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
    is($verdict, 'GAP', 'D6 ir block declares L: GAP');
};

# ---------------------------------------------------------------------------
# SECTION 5: Negative guard — a control-flow case claiming GREEN must FAIL
#
# If someone edits a control-flow case to claim L: GREEN without actually
# building a lowerable graph, the runner must catch the lie.  We test this
# with a fake if/else case that claims GREEN — the pure-GAP block (no nodes)
# combined with a GREEN claim is the inconsistency the runner detects.
# ---------------------------------------------------------------------------

subtest 'guard: pure-GAP block with L: GREEN for control-flow FAILS L verdict' => sub {
    my $fake_green_md = <<'END_MD';
# Fake

## Fake GREEN if/else case

```perl
# source
my $n = 5; my $x; if ($n > 0) { $x = 1 } else { $x = 2 }; $x
```

```behavior
return: 1
context: scalar
```

```ir
L: GREEN
```
END_MD

    use File::Temp qw(tempfile);
    my ($fh, $tmpfile) = tempfile(SUFFIX => '.md', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $fake_green_md;
    close $fh;

    my $fake_cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($tmpfile);
    my $fake_case  = $fake_cases->[0];
    my $result     = Chalk::CodeGen::Harness::MdtestCorpus->run_case($fake_case, {});

    is($result->{l_verdict}{verdict}, 'FAIL',
        'pure-GAP block (no nodes) claiming L: GREEN is FAIL');
    is($result->{overall}, 'FAIL', 'overall is FAIL');
    ok(scalar(@{ $result->{fail_reasons} }) > 0, 'at least one fail reason recorded');
    like($result->{fail_reasons}[0] // '', qr/L verdict|GAP|GREEN/i,
        'fail reason mentions L verdict, GAP, or GREEN');
};

done_testing;
