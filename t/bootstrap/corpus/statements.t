# ABOUTME: Runner for the statements mdtest corpus topic (constructive format).
# ABOUTME: Covers return-integer, multi-statement, comparison-as-condition GREEN, and pragma GAP idioms.
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

my $STATEMENTS_MD = 't/corpus/mdtest/statements.md';

unless (-f $STATEMENTS_MD) {
    plan skip_all => "statements.md not found at $STATEMENTS_MD";
}

# ---------------------------------------------------------------------------
# SECTION 1: Parse statements.md and verify case inventory
#
# All 5 statement idioms must be present.
# - Return integer literal: GREEN (Constant -> Return, simplest runtime-free)
# - Multiple statements: GREEN (two VarDecls + Add, straight-line SSA)
# - Comparison as condition (1<2?1:0): GREEN (TernaryExpr/select -> Int; bool is a condition not a value)
# - Pragma (use strict): GAP (compile-time directive, no SoN IR node)
# - Pragma with import (use Module qw(...)): GAP (compile-time import)
#
# The corpus MUST record these GAPs honestly — a GREEN claim for any GAP case
# would be a lie and must fail.
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($STATEMENTS_MD);
is(scalar(@$cases), 5, 'statements.md has 5 cases');

my @titles = map { $_->{title} } @$cases;
ok((grep { /return.*integer.*literal/i || /return.*5/i } @titles),
    'case: return integer literal present');
ok((grep { /multiple.*statements/i } @titles),
    'case: multiple statements present');
ok((grep { /comparison.*chain/i || /1.*<.*2/i } @titles),
    'case: comparison chain present');
ok((grep { /pragma.*declaration.*use.*strict/i || /use strict/i } @titles),
    'case: pragma use strict present');
ok((grep { /pragma.*import.*list/i || /use.*list.*util/i || /use.*qw/i } @titles),
    'case: pragma with import list present');

# ---------------------------------------------------------------------------
# SECTION 2: Run all 5 cases end-to-end
#
# For each case:
#   - behavior check must PASS (perl oracle vs declared return value)
#   - ir-shape check must not FAIL (pure-GAP blocks trivially pass)
#   - L-verdict check must PASS (declared verdict matches actual verdict)
#
# GREEN cases (return-integer, multiple-statements) have constructive ir blocks
# that build real graphs; L-corner runs them and verifies lli output == perl.
# GAP cases (comparison-chain, use-strict, use-Module-qw) are pure-GAP blocks
# with no buildable graph; the L check verifies declared GAP is consistent.
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

        # L-verdict check: declared verdict must match actual verdict
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
# return-integer and multiple-statements declare L: GREEN (constructive graphs).
# comparison-chain, use-strict, and use-Module-qw declare L: GAP.
# ---------------------------------------------------------------------------

subtest 'L-verdict declarations: GREEN for return/multi, GAP for comparison/pragma' => sub {
    plan tests => 5;

    for my $case (@$cases) {
        my $ir_text = $case->{ir} // '';
        my $decl    = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        my $title   = $case->{title};

        # GREEN: return-integer, multiple-statements, and comparison-as-condition
        # (1 < 2 ? 1 : 0 -> Int via TernaryExpr/select; the bool is an internal
        # condition, never a returned value — bool-as-VALUE would need Str/group-C).
        if (   $title =~ /return.*integer.*literal/i
            || $title =~ /multiple.*statement/i
            || $title =~ /comparison.*condition/i) {
            is($decl, 'GREEN', "case '$title': declared L: GREEN");
        } else {
            is($decl, 'GAP', "case '$title': declared L: GAP");
        }
    }
};

# ---------------------------------------------------------------------------
# SECTION 4: Constructive proofs for the two GREEN cases
#
# Verify that build_graph_from_ir builds real graphs from the ir blocks and
# that LLVMDriver lowers them without marking them unsupported.
# lli output must agree with the perl oracle.
# ---------------------------------------------------------------------------

subtest 'constructive proof: return integer literal builds and lowers to 5' => sub {
    my ($case) = grep { $_->{title} =~ /return.*integer.*literal/i } @$cases;
    ok(defined $case, 'return-integer case found');

    my $ir_text = $case->{ir} // '';

    my $return_node;
    eval {
        $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text);
    };
    ok(!$@, "return-integer build_graph_from_ir does not croak")
        or diag("build error: $@");
    ok(defined $return_node, 'return-integer build_graph_from_ir returns a defined Return node');

    my $verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
    is($verdict, 'GREEN', 'return-integer ir block declares L: GREEN');

    if (defined $return_node) {
        my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
        ok(!$meta->{marked_unsupported},
            'return-integer graph is truly GREEN (not marked_unsupported)');
        my $lli_out = $L->return_values->[0] // '';
        is($lli_out, '5', 'return-integer lli output is 5');
        is($lli_out, $case->{_perl_actual} // '5',
            'return-integer lli output matches perl oracle');
    }
};

subtest 'constructive proof: multiple-statements builds and lowers to 3' => sub {
    my ($case) = grep { $_->{title} =~ /multiple.*statements/i } @$cases;
    ok(defined $case, 'multiple-statements case found');

    my $ir_text = $case->{ir} // '';

    my $return_node;
    eval {
        $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text);
    };
    ok(!$@, "multiple-statements build_graph_from_ir does not croak")
        or diag("build error: $@");
    ok(defined $return_node, 'multiple-statements build_graph_from_ir returns a defined Return node');

    my $verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
    is($verdict, 'GREEN', 'multiple-statements ir block declares L: GREEN');

    if (defined $return_node) {
        my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
        ok(!$meta->{marked_unsupported},
            'multiple-statements graph is truly GREEN (not marked_unsupported)');
        my $lli_out = $L->return_values->[0] // '';
        is($lli_out, '3', 'multiple-statements lli output is 3');
        is($lli_out, $case->{_perl_actual} // '3',
            'multiple-statements lli output matches perl oracle');
    }
};

# ---------------------------------------------------------------------------
# SECTION 5: Negative guard — a pure-GAP block with L: GREEN must FAIL
#
# If someone marks a comparison-chain or pragma case as L: GREEN without
# building a real lowerable graph, the runner detects the inconsistency.
# This guard proves the honesty mechanism is active.
# ---------------------------------------------------------------------------

subtest 'guard: pure-GAP block with L: GREEN for comparison FAILS L verdict' => sub {
    my $fake_green_md = <<'END_MD';
# Fake

## Fake GREEN comparison case

```perl
# source
1 < 2
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
