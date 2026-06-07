# ABOUTME: Runner for the control-flow mdtest corpus topic (constructive format).
# ABOUTME: Exercises D1-D8 control-flow idioms: D6 is GREEN (TernaryExpr -> select i1); D1-D5/D7/D8 are LLVM GAPs.
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
#   - L-verdict check must PASS (declared verdict matches actual verdict)
#
# D6 declares L: GREEN — the 3-input TernaryExpr builder builds the graph
# and the LLVM backend lowers it via select i1.  lli output must match perl.
# D1-D5/D7/D8 are genuine LLVM GAPs (br + phi or landingpad not in the
# current lowering slice).
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
# SECTION 3: Verify L-verdict declarations per case
#
# D6 declares L: GREEN — the 3-input TernaryExpr builder can now construct
# the graph, and the LLVM backend lowers it via select i1.
# D1-D5, D7, D8 all declare L: GAP (br + phi or landingpad not yet in the
# lowering slice).
# ---------------------------------------------------------------------------

subtest 'D6 declares L: GREEN; D1-D5/D7/D8 declare L: GAP' => sub {
    plan tests => 8;
    for my $case (@$cases) {
        my $ir_text = $case->{ir} // '';
        my $decl    = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        my $title   = $case->{title};
        if ($title =~ /D6.*ternary/i) {
            is($decl, 'GREEN', "case '$title': declared L: GREEN (TernaryExpr via select i1)");
        } else {
            is($decl, 'GAP',   "case '$title': declared L: GAP (not lowerable as straight-line code)");
        }
    }
};

# ---------------------------------------------------------------------------
# SECTION 4: D6 constructive proof — TernaryExpr builds and lowers correctly
#
# D6 now has a constructive ir block (not pure-GAP). Verify that:
#   - build_graph_from_ir builds a real TernaryExpr graph from the block
#   - the built graph lowers via LLVMDriver without being marked_unsupported
#   - lli output is 1 (5 > 0 is true, select branch 1)
#   - lli output matches the perl oracle (also 1)
# This is the load-bearing proof that D6 is truly GREEN, not just claimed GREEN.
# ---------------------------------------------------------------------------

subtest 'D6 constructive proof: TernaryExpr builds and lowers to 1 via lli' => sub {
    my ($d6_case) = grep { $_->{title} =~ /D6.*ternary/i } @$cases;
    ok(defined $d6_case, 'D6 case found');

    my $ir_text = $d6_case->{ir} // '';

    # The D6 ir block now has node lines (not pure-GAP)
    my $return_node;
    eval {
        $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text);
    };
    ok(!$@, "D6 build_graph_from_ir does not croak (got: $@)")
        or diag("build error: $@");
    ok(defined $return_node, 'D6 build_graph_from_ir returns a defined Return node');

    # The L verdict must be GREEN
    my $verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
    is($verdict, 'GREEN', 'D6 ir block declares L: GREEN');

    if (defined $return_node) {
        my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
        ok(!$meta->{marked_unsupported},
            'D6 TernaryExpr graph is truly GREEN (not marked_unsupported)');
        my $lli_out = $L->return_values->[0] // '';
        is($lli_out, '1', "D6 lli output is 1 (5>0 true -> select then-branch)");
        is($lli_out, $d6_case->{_perl_actual} // '1',
            "D6 lli output matches perl oracle");
    }
};

# ---------------------------------------------------------------------------
# SECTION 5: Negative guard — a non-lowerable control-flow case claiming GREEN must FAIL
#
# If someone edits a D1-D5/D7/D8 case to claim L: GREEN without actually
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
