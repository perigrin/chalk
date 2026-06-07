# ABOUTME: Runner for the logical-operators mdtest corpus topic (constructive format).
# ABOUTME: Exercises L1-L4 logical idioms: &&, ||, //, ! — all are honest GAPs (no runtime-free lowering).
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

my $LOGICAL_MD = 't/corpus/mdtest/logical.md';

unless (-f $LOGICAL_MD) {
    plan skip_all => "logical.md not found at $LOGICAL_MD";
}

# ---------------------------------------------------------------------------
# SECTION 1: Parse logical.md and verify case inventory
#
# All 4 logical idioms (L1-L4) must be present.  All four declare L: GAP
# because:
#   L1 (&&): operand-returning; needs If+Phi short-circuit
#   L2 (||): operand-returning; needs If+Phi short-circuit
#   L3 (//): SvOK defined-check; inherently a Scalar runtime operation
#   L4 (!):  returns "" not 0 for truthy input; dual-representation Str result
# A GREEN claim for any of them would be a lie and must fail.
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($LOGICAL_MD);
is(scalar(@$cases), 4, 'logical.md has 4 cases (L1-L4)');

my @titles = map { $_->{title} } @$cases;
ok((grep { /L1.*logical.*and/i } @titles),  'case: L1 logical and present');
ok((grep { /L2.*logical.*or/i  } @titles),  'case: L2 logical or present');
ok((grep { /L3.*defined.*or/i  } @titles),  'case: L3 defined-or present');
ok((grep { /L4.*not/i          } @titles),  'case: L4 not present');

# ---------------------------------------------------------------------------
# SECTION 2: Run all 4 cases end-to-end
#
# For each case:
#   - behavior check must PASS (perl oracle vs declared return value)
#   - ir-shape check must not FAIL (pure-GAP blocks trivially pass)
#   - L-verdict check must PASS (declared GAP matches actual GAP)
#
# All four cases declare L: GAP — none can be lowered runtime-free by the
# current literal-arithmetic lowering slice.
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
# SECTION 3: Verify all four cases declare L: GAP
#
# None of these idioms are runtime-free lowerable:
#   L1 (&&): operand-returning short-circuit — needs If+Phi
#   L2 (||): operand-returning short-circuit — needs If+Phi
#   L3 (//): SvOK defined-check — Scalar runtime operation
#   L4 (!):  "" vs "1" dual-representation — not integer 0/1
# ---------------------------------------------------------------------------

subtest 'all four logical cases declare L: GAP' => sub {
    plan tests => 4;
    for my $case (@$cases) {
        my $ir_text = $case->{ir} // '';
        my $decl    = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        my $title   = $case->{title};
        is($decl, 'GAP', "case '$title': declared L: GAP");
    }
};

# ---------------------------------------------------------------------------
# SECTION 4: All four cases are pure-GAP blocks (no buildable nodes)
#
# A pure-GAP block has an L: GAP(...) line and no %name = ... node lines.
# Verify build_graph_from_ir returns undef for each case (no graph to build).
# ---------------------------------------------------------------------------

subtest 'all four logical cases are pure-GAP blocks (build_graph_from_ir returns undef)' => sub {
    plan tests => 4;
    for my $case (@$cases) {
        my $ir_text = $case->{ir} // '';
        my $return_node;
        eval { $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text) };
        my $title = $case->{title};
        ok(!defined $return_node && !$@,
            "case '$title': build_graph_from_ir returns undef (pure-GAP, no error)");
    }
};

# ---------------------------------------------------------------------------
# SECTION 5: Negative guard — a logical case claiming L: GREEN must FAIL
#
# If someone edits a logical case to claim L: GREEN without building a
# lowerable graph, the runner must catch the lie.  A pure-GAP block
# (no node lines) combined with a GREEN claim is the inconsistency the
# runner detects.
# ---------------------------------------------------------------------------

subtest 'guard: pure-GAP block with L: GREEN for logical op FAILS L verdict' => sub {
    my $fake_green_md = <<'END_MD';
# Fake

## Fake GREEN and case

```perl
# source
my $a = 3; my $b = 7; $a && $b
```

```behavior
return: 7
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
