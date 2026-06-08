# ABOUTME: Runner for the statements mdtest corpus topic (constructive format).
# ABOUTME: Covers return-integer, multi-statement, bare-bool GREEN, comparison-as-condition, and pragma GAP.
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
# All 7 statement idioms must be present.
# - Return integer literal: GREEN (Constant -> Return, simplest runtime-free)
# - Multiple statements: GREEN (two VarDecls + Add, straight-line SSA)
# - Comparison as condition (1<2?1:0): GREEN (TernaryExpr/select -> Int; bool internal)
# - Bare bool return true (1 < 2): GREEN (NumLt -> Bool:1, type-tagged)
# - Bare bool return false (2 < 1): GREEN (NumLt -> Bool:, type-tagged)
# - Pragma (use strict): GAP (compile-time directive, no SoN IR node)
# - Pragma with import (use Module qw(...)): GAP (compile-time import)
#
# The corpus MUST record these GAPs honestly — a GREEN claim for any GAP case
# would be a lie and must fail. The bilateral bare-bool coverage (true + false)
# ensures a one-sided miscompile cannot hide: false must emit Bool:, NOT Str:
# or Int:0.
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($STATEMENTS_MD);
is(scalar(@$cases), 7, 'statements.md has 7 cases');

my @titles = map { $_->{title} } @$cases;
ok((grep { /return.*integer.*literal/i || /return.*5/i } @titles),
    'case: return integer literal present');
ok((grep { /multiple.*statements/i } @titles),
    'case: multiple statements present');
ok((grep { /comparison.*chain/i || /1.*<.*2.*\?/i } @titles),
    'case: comparison as condition (ternary) present');
ok((grep { /bare.*bool.*return.*true/i || /1.*<.*2.*bare/i || /bare.*bool.*true/i } @titles),
    'case: bare bool return true (1 < 2) present');
ok((grep { /bare.*bool.*return.*false/i || /2.*<.*1.*bare/i || /bare.*bool.*false/i } @titles),
    'case: bare bool return false (2 < 1) present');
ok((grep { /pragma.*declaration.*use.*strict/i || /use strict/i } @titles),
    'case: pragma use strict present');
ok((grep { /pragma.*import.*list/i || /use.*list.*util/i || /use.*qw/i } @titles),
    'case: pragma with import list present');

# ---------------------------------------------------------------------------
# SECTION 2: Run all 7 cases end-to-end
#
# For each case:
#   - behavior check must PASS (perl oracle vs declared return value)
#   - ir-shape check must not FAIL (pure-GAP blocks trivially pass)
#   - L-verdict check must PASS (declared verdict matches actual verdict)
#
# GREEN cases have constructive ir blocks; L-corner verifies lli output == perl.
# GAP cases (use-strict, use-Module-qw) are pure-GAP blocks.
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
# GREEN: return-integer, multiple-statements, comparison-as-condition (ternary),
#        bare-bool-return-true, bare-bool-return-false.
# GAP: use-strict, use-Module-qw.
# ---------------------------------------------------------------------------

subtest 'L-verdict declarations: GREEN for value cases, GAP for pragma cases' => sub {
    plan tests => 7;

    for my $case (@$cases) {
        my $ir_text = $case->{ir} // '';
        my $decl    = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        my $title   = $case->{title};

        if (   $title =~ /return.*integer.*literal/i
            || $title =~ /multiple.*statement/i
            || $title =~ /comparison.*condition/i
            || $title =~ /bare.*bool/i) {
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
        is($lli_out, 'Int:5', 'return-integer lli output is Int:5 (type-tagged)');
        is($lli_out, $case->{_perl_actual} // 'Int:5',
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
        is($lli_out, 'Int:3', 'multiple-statements lli output is Int:3 (type-tagged)');
        is($lli_out, $case->{_perl_actual} // 'Int:3',
            'multiple-statements lli output matches perl oracle');
    }
};

# ---------------------------------------------------------------------------
# SECTION 5: Bare-bool constructive proofs — NumLt lowers to Bool with type-tag
#
# Both true (1 < 2 => Bool:1) and false (2 < 1 => Bool:) cases must lower GREEN.
# Bilateral coverage rule: both sides are checked so a one-sided miscompile
# (e.g. false lowered as Int:0 or Str: instead of Bool:) cannot hide.
# ---------------------------------------------------------------------------

subtest 'constructive proof: bare bool true (1<2) builds and lowers to Bool:1' => sub {
    my ($case) = grep { $_->{title} =~ /bare.*bool.*true/i } @$cases;
    ok(defined $case, 'bare-bool-true case found');

    my $ir_text = $case->{ir} // '';

    my $return_node;
    eval { $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text) };
    ok(!$@, "bare-bool-true build_graph_from_ir does not croak (got: $@)")
        or diag("build error: $@");
    ok(defined $return_node, 'bare-bool-true build_graph_from_ir returns a defined Return node');

    my $verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
    is($verdict, 'GREEN', 'bare-bool-true ir block declares L: GREEN');

    if (defined $return_node) {
        my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
        ok(!$meta->{marked_unsupported},
            'bare-bool-true graph is truly GREEN (not marked_unsupported)')
            or diag("gap: " . ($meta->{gap_reason} // 'none') . "\nerr: " . ($meta->{lower_error} // 'none'));

        my $ll = $meta->{ll_text} // '';
        unlike($ll, qr/Perl_/,   'bare-bool-true .ll: no Perl_ C-API symbols');
        unlike($ll, qr/\bSV\b/,  'bare-bool-true .ll: no SV type symbols');
        unlike($ll, qr/sv_/,     'bare-bool-true .ll: no sv_ C-API symbols');
        unlike($ll, qr/libperl/, 'bare-bool-true .ll: no libperl reference');

        my $lli_out = $L->return_values->[0] // '';
        is($lli_out, 'Bool:1', 'bare-bool-true lli output is Bool:1 (type-tagged)');
        is($lli_out, $case->{_perl_actual} // 'Bool:1',
            'bare-bool-true lli output matches perl oracle');
    }
};

subtest 'constructive proof: bare bool false (2<1) builds and lowers to Bool:' => sub {
    my ($case) = grep { $_->{title} =~ /bare.*bool.*false/i } @$cases;
    ok(defined $case, 'bare-bool-false case found');

    my $ir_text = $case->{ir} // '';

    my $return_node;
    eval { $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text) };
    ok(!$@, "bare-bool-false build_graph_from_ir does not croak (got: $@)")
        or diag("build error: $@");
    ok(defined $return_node, 'bare-bool-false build_graph_from_ir returns a defined Return node');

    my $verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
    is($verdict, 'GREEN', 'bare-bool-false ir block declares L: GREEN');

    if (defined $return_node) {
        my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
        ok(!$meta->{marked_unsupported},
            'bare-bool-false graph is truly GREEN (not marked_unsupported)')
            or diag("gap: " . ($meta->{gap_reason} // 'none') . "\nerr: " . ($meta->{lower_error} // 'none'));

        my $ll = $meta->{ll_text} // '';
        unlike($ll, qr/Perl_/,   'bare-bool-false .ll: no Perl_ C-API symbols');
        unlike($ll, qr/\bSV\b/,  'bare-bool-false .ll: no SV type symbols');
        unlike($ll, qr/sv_/,     'bare-bool-false .ll: no sv_ C-API symbols');
        unlike($ll, qr/libperl/, 'bare-bool-false .ll: no libperl reference');

        my $lli_out = $L->return_values->[0] // '';
        # Bool: (false, empty string-face) — NOT Int:0 or Str: (wrong type identity).
        is($lli_out, 'Bool:', 'bare-bool-false lli output is Bool: (type-tagged, NOT Int:0 or Str:)');
        is($lli_out, $case->{_perl_actual} // 'Bool:',
            'bare-bool-false lli output matches perl oracle');
    }
};

# ---------------------------------------------------------------------------
# SECTION 6: Adversarial guard — Bool identity miscompiles MUST FAIL
#
# Part D: the type-discriminating oracle makes it mechanically enforceable that:
# (a) A graph returning a raw Int 0/1 where perl returns Bool:false/Bool:true
#     produces a TAG MISMATCH (Int:0 vs Bool:) and FAILS.
# (b) A graph returning Str: where perl returns Bool: also FAILS (Str: != Bool:).
#
# These are NOT theoretical — they are the exact miscompiles that would arise
# from modelling Bool as integer 0/1 or as empty string. The oracle catches both.
# ---------------------------------------------------------------------------

subtest 'adversarial guard: Bool lowered as raw Int FAILS oracle compare' => sub {
    use File::Temp qw(tempfile);
    # Source: `!5` => Bool:false. If we return a plain Int 0 instead of Bool, we get
    # Int:0 from lli but Bool: from perl — tag mismatch => FAIL.
    my $bad_md = <<'END_MD';
# Adversarial

## Bool-as-Int miscompile guard

```perl
# source
my $a = 5;
!$a
```

```behavior
return: Bool:
context: scalar
```

```ir
%c5   = Constant(5) :Int
%zero = Constant(0) :Int
return %zero
L: GREEN
```
END_MD

    my ($fh, $tmpfile) = tempfile(SUFFIX => '.md', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $bad_md;
    close $fh;

    my $cases  = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($tmpfile);
    my $case   = $cases->[0];
    my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {});

    # The graph returns Int:0 but perl oracle returns Bool: — tag mismatch.
    is($result->{l_verdict}{verdict}, 'FAIL',
        'Bool-as-Int graph (returns Int:0 where Bool: expected): L verdict FAILS');
    is($result->{overall}, 'FAIL',
        'Bool-as-Int adversarial: overall FAIL');
    ok(scalar(@{ $result->{fail_reasons} }) > 0,
        'Bool-as-Int adversarial: at least one fail reason');
    like(join(' ', @{ $result->{fail_reasons} }), qr/Int:0|Bool:|mismatch/i,
        'Bool-as-Int adversarial: fail reason mentions Int:0, Bool: or mismatch');
};

# ---------------------------------------------------------------------------
# SECTION 7: Negative guard — a pure-GAP block with L: GREEN must FAIL
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
