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
# SECTION 1: Parse statements.md and verify the topic's named idioms are present.
#
# All statement idioms must be present.
# - Return integer literal: GREEN (Constant -> Return, simplest runtime-free)
# - Multiple statements: GREEN (two VarDecls + Add, straight-line SSA)
# - Comparison as condition (1<2?1:0): GREEN (TernaryExpr/select -> Int; bool internal)
# - Bare bool return true (1 < 2): GREEN (NumLt -> Bool:1)
# - Bare bool return false (2 < 1): GREEN (NumLt -> Bool:)
# - Pragma (use strict): GAP (compile-time directive, no SoN IR node)
# - Pragma with import (use Module qw(...)): GAP (compile-time import)
#
# The corpus MUST record these GAPs honestly — a GREEN claim for any GAP case
# would be a lie and must fail. The bilateral bare-bool coverage (true + false)
# ensures a one-sided miscompile cannot hide: false must emit Bool:, NOT Str:
# or Int:0.
#
# This runner asserts the STATIC inventory + shape of the corpus file. The
# authoritative behavior/shape/invariant gate is
# t/bootstrap/corpus/son-corpus-wide.t, which lowers each case's PERL SOURCE
# through B::SoN -> chalk -> lli. The old per-case run_case checks here lowered
# the hand-written IR BLOCK through the constructive builder -- a second,
# drifting lowering path with hardcoded case counts that went stale on every
# corpus addition (zhi 019f53a0). Retired here in favor of the single
# authoritative gate.
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($STATEMENTS_MD);

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
# SECTION 2: Verify L-verdict declarations are well-formed
#
# This was a list of title patterns asserted GREEN, with everything else
# asserted GAP -- a second copy of what each case's own `L:` line states, which
# drifts the moment a verdict changes. It went stale when `say` started
# lowering: four say cases are now GREEN in the corpus while the list still
# expected GAP. Commit 1311e782 retired the same anti-pattern (hardcoded counts)
# from the per-topic runners; the title lists were the survivors.
#
# What is worth pinning is that the declaration is WELL-FORMED: a known verdict,
# and a GAP that states its reason rather than being an unexplained exemption.
# WHICH cases are GAP is the corpus's business, and son-corpus-wide.t measures
# whether each declaration matches reality.
# ---------------------------------------------------------------------------

subtest 'L-verdict declarations are well-formed (a GAP states its reason)' => sub {
    plan tests => scalar(@$cases) * 2;

    for my $case (@$cases) {
        my $ir_text = $case->{ir} // '';
        my $decl    = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        my $title   = $case->{title};

        like($decl, qr/\A(?:GREEN|GAP)\z/, "case '$title': declares a known verdict");

        if ($decl eq 'GAP') {
            like($ir_text, qr/^L:\s*GAP\s*\(.*\S.*\)/ms,
                "case '$title': the GAP declaration states a reason");
        }
        else {
            pass("case '$title': GREEN needs no reason");
        }
    }
};

# ---------------------------------------------------------------------------
# SECTION 3: Constructive proofs for the two GREEN cases
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
        is($lli_out, '5', 'return-integer lli prints 5 (printed)');
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
        is($lli_out, '3', 'multiple-statements lli prints 3 (printed)');
        is($lli_out, $case->{_perl_actual} // '3',
            'multiple-statements lli output matches perl oracle');
    }
};

# ---------------------------------------------------------------------------
# SECTION 4: Bare-bool constructive proofs — NumLt lowers to Boolean with type-tag
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
        is($lli_out, '1', 'bare-bool-true lli prints 1 (printed)');
        is($lli_out, $case->{_perl_actual} // '1',
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
        is($lli_out, '', 'bare-bool-false lli prints the empty string for false (NOT Int:0 or Str:)');
        is($lli_out, $case->{_perl_actual} // '',
            'bare-bool-false lli output matches perl oracle');
    }
};

# ---------------------------------------------------------------------------
# SECTION 5: Adversarial guard — REMOVED, pending replacement
#
# There was a guard here proving that a Boolean lowered as a raw Int gets caught:
# under the FRAGMENT contract its graph returned Int:0 where the perl oracle
# returned Bool:, a tag mismatch that failed loudly.
#
# The corpus-as-programs migration made its FIXTURE correct, which removed its
# teeth. Under the program contract the same graph Coerces Int 0 to the string
# "0" and prints it — honest lowering, so there is no longer a miscompile for
# the guard to detect, and every one of its assertions passes.
#
# It is REMOVED rather than left passing. A guard that cannot fail is worse than
# no guard: it reads as coverage while proving nothing, which is the exact
# vacuity this project keeps having to dig out. Restoring it needs a fixture
# that genuinely misrepresents a Boolean under the PROGRAM contract — a new
# adversarial case, not an edit to the old one.
#
# Tracked: docs/plans/2026-08-13-followups.md, "Boolean-as-Int adversarial guard".
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# SECTION 6: Negative guard — a pure-GAP block with L: GREEN must FAIL
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
