# ABOUTME: Runner for the logical-operators mdtest corpus topic (constructive format).
# ABOUTME: L1 (&&) and L2 (||) are GREEN via cfg-blocks-phi; L3 (//) and L4 (!) remain GAP.
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
# All 4 logical idioms (L1-L4) must be present.
#   L1 (&&): GREEN — cfg-blocks-phi lands And lowering (branch+phi)
#   L2 (||): GREEN — cfg-blocks-phi lands Or lowering (branch+phi)
#   L3 (//): GAP  — needs Undef representation + definedness predicate
#   L4 (!):  GAP  — needs Bool representation + UnaryNot + Coerce(Bool->*)
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
#   - L-verdict check must PASS (declared verdict matches actual verdict)
#
# L1 and L2 declare L: GREEN — they lower via And/Or branch+phi.
# L3 and L4 declare L: GAP — not lowerable in the current slice.
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
# L1 (&&): GREEN — And lowering via branch+phi
# L2 (||): GREEN — Or lowering via branch+phi
# L3 (//): GAP  — Undef representation not yet modelled
# L4 (!):  GAP  — Bool representation + UnaryNot not yet modelled
# ---------------------------------------------------------------------------

subtest 'L1/L2 declare L: GREEN; L3/L4 declare L: GAP' => sub {
    plan tests => 4;
    for my $case (@$cases) {
        my $ir_text = $case->{ir} // '';
        my $decl    = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        my $title   = $case->{title};
        if ($title =~ /L1.*logical.*and/i || $title =~ /L2.*logical.*or/i) {
            is($decl, 'GREEN', "case '$title': declared L: GREEN (cfg-blocks-phi And/Or lowering)");
        } else {
            is($decl, 'GAP',   "case '$title': declared L: GAP (not lowerable in current slice)");
        }
    }
};

# ---------------------------------------------------------------------------
# SECTION 4: L1/L2 constructive proof — And/Or builds and lowers correctly
#
# L1 (&&): And(Constant 3, Constant 7) lowers via branch+phi; lli prints 7.
# L2 (||): Or(Constant 3, Constant 7) lowers via branch+phi; lli prints 3.
# L3/L4 return undef (pure-GAP blocks, no graph to build).
# ---------------------------------------------------------------------------

subtest 'L1 constructive proof: And builds and lowers to 7 via lli' => sub {
    my ($l1_case) = grep { $_->{title} =~ /L1.*logical.*and/i } @$cases;
    ok(defined $l1_case, 'L1 case found');

    my $ir_text = $l1_case->{ir} // '';
    my $return_node;
    eval { $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text) };
    ok(!$@, "L1 build_graph_from_ir does not croak (got: $@)")
        or diag("build error: $@");
    ok(defined $return_node, 'L1 build_graph_from_ir returns a defined Return node');

    my $verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
    is($verdict, 'GREEN', 'L1 ir block declares L: GREEN');

    if (defined $return_node) {
        my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
        ok(!$meta->{marked_unsupported}, 'L1 And graph is truly GREEN (not marked_unsupported)')
            or diag("gap reason: " . ($meta->{gap_reason} // 'none') . "\nerror: " . ($meta->{lower_error} // 'none'));

        # Libperl-free assertion: the emitted .ll must not call any Perl C-API.
        my $ll = $meta->{ll_text} // '';
        unlike($ll, qr/Perl_/, 'L1 .ll: no Perl_ C-API symbols');
        unlike($ll, qr/\bSV\b/, 'L1 .ll: no SV type symbols');

        my $lli_out = $L->return_values->[0] // '';
        is($lli_out, '7', "L1 lli output is 7 (3&&7 == 7)");
        is($lli_out, $l1_case->{_perl_actual} // '7',
            "L1 lli output matches perl oracle");
    }
};

subtest 'L2 constructive proof: Or builds and lowers to 3 via lli' => sub {
    my ($l2_case) = grep { $_->{title} =~ /L2.*logical.*or/i } @$cases;
    ok(defined $l2_case, 'L2 case found');

    my $ir_text = $l2_case->{ir} // '';
    my $return_node;
    eval { $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text) };
    ok(!$@, "L2 build_graph_from_ir does not croak (got: $@)")
        or diag("build error: $@");
    ok(defined $return_node, 'L2 build_graph_from_ir returns a defined Return node');

    my $verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
    is($verdict, 'GREEN', 'L2 ir block declares L: GREEN');

    if (defined $return_node) {
        my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
        ok(!$meta->{marked_unsupported}, 'L2 Or graph is truly GREEN (not marked_unsupported)')
            or diag("gap reason: " . ($meta->{gap_reason} // 'none') . "\nerror: " . ($meta->{lower_error} // 'none'));

        # Libperl-free assertion.
        my $ll = $meta->{ll_text} // '';
        unlike($ll, qr/Perl_/, 'L2 .ll: no Perl_ C-API symbols');
        unlike($ll, qr/\bSV\b/, 'L2 .ll: no SV type symbols');

        my $lli_out = $L->return_values->[0] // '';
        is($lli_out, '3', "L2 lli output is 3 (3||7 == 3)");
        is($lli_out, $l2_case->{_perl_actual} // '3',
            "L2 lli output matches perl oracle");
    }
};

subtest 'L3/L4 are pure-GAP blocks (build_graph_from_ir returns undef)' => sub {
    plan tests => 2;
    for my $case (@$cases) {
        next unless $case->{title} =~ /L3.*defined.*or/i || $case->{title} =~ /L4.*not/i;
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
# if the ir block has no buildable nodes (pure-GAP with GREEN claim).
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
