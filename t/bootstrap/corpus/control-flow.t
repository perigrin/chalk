# ABOUTME: Runner for the control-flow mdtest corpus topic (constructive format).
# ABOUTME: D6 (ternary->select) and D1/D2/D3/D4/D5/D7 (cfg-blocks-phi) are GREEN; D8 (try/catch) is GAP.
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
# All 8 control-flow idioms (D1-D8) must be present.
#   D6: GREEN via TernaryExpr -> select i1
#   D1/D2/D3/D4/D5/D7: GREEN via cfg-blocks-phi (br + phi)
#   D8: GAP (needs LLVM landingpad — different capability)
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($CONTROL_FLOW_MD);
is(scalar(@$cases), 9, 'control-flow.md has 9 cases (D1-D9)');

my @titles = map { $_->{title} } @$cases;
ok((grep { /D6.*ternary/i } @titles),    'case: D6 ternary present');
ok((grep { /D1.*if.*else/i } @titles),   'case: D1 if/else present');
ok((grep { /D2.*while/i }   @titles),    'case: D2 while present');
ok((grep { /D3.*foreach/i } @titles),    'case: D3 foreach present');
ok((grep { /D4.*postfix.*if/i } @titles),'case: D4 postfix if present');
ok((grep { /D5.*postfix.*while/i } @titles), 'case: D5 postfix while present');
ok((grep { /D7.*nested/i }  @titles),    'case: D7 nested if present');
ok((grep { /D8.*try/i }     @titles),    'case: D8 try/catch present');
ok((grep { /D9.*nested.*runtime/i } @titles), 'case: D9 nested if runtime-false present');

# ---------------------------------------------------------------------------
# SECTION 2: Run all 8 cases end-to-end
#
# For each case:
#   - behavior check must PASS (perl oracle vs declared return value)
#   - ir-shape check must not FAIL
#   - L-verdict check must PASS (declared verdict matches actual verdict)
#
# D6, D1-D5, D7 declare L: GREEN.
# D8 declares L: GAP (landingpad not in this scope).
# ---------------------------------------------------------------------------

for my $case (@$cases) {
    my $title = $case->{title};

    subtest "case: $title" => sub {
        my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {});

        is($result->{behavior}{verdict}, 'PASS',
            "$title: behavior oracle matches")
            or diag("  behavior fail: " . join('; ', @{ $result->{fail_reasons} }));

        isnt($result->{ir_shape}{verdict}, 'FAIL',
            "$title: ir-shape not FAIL")
            or diag("  ir-shape fail: " . join('; ', @{ $result->{fail_reasons} }));

        is($result->{l_verdict}{verdict}, 'PASS',
            "$title: L verdict matches")
            or diag("  L fail: " . join('; ', @{ $result->{fail_reasons} }));

        is($result->{overall}, 'PASS', "$title: overall PASS")
            or diag("  fail reasons: " . join('; ', @{ $result->{fail_reasons} }));
    };
}

# ---------------------------------------------------------------------------
# SECTION 3: Verify L-verdict declarations per case
#
# D8 (try/catch) is the only remaining GAP — needs LLVM landingpad.
# D6 (ternary) + D1-D5 + D7 are GREEN via their respective lowering paths.
# ---------------------------------------------------------------------------

subtest 'D1-D7 and D9 declare L: GREEN; D8 declares L: GAP' => sub {
    plan tests => 9;
    for my $case (@$cases) {
        my $ir_text = $case->{ir} // '';
        my $decl    = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        my $title   = $case->{title};
        if ($title =~ /D8.*try/i) {
            is($decl, 'GAP', "case '$title': declared L: GAP (try/catch needs landingpad)");
        } else {
            is($decl, 'GREEN', "case '$title': declared L: GREEN");
        }
    }
};

# ---------------------------------------------------------------------------
# SECTION 4: D6 constructive proof — TernaryExpr builds and lowers correctly
# ---------------------------------------------------------------------------

subtest 'D6 constructive proof: TernaryExpr builds and lowers to 1 via lli' => sub {
    my ($d6_case) = grep { $_->{title} =~ /D6.*ternary/i } @$cases;
    ok(defined $d6_case, 'D6 case found');

    my $ir_text = $d6_case->{ir} // '';
    my $return_node;
    eval { $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text) };
    ok(!$@, "D6 build_graph_from_ir does not croak (got: $@)")
        or diag("build error: $@");
    ok(defined $return_node, 'D6 build_graph_from_ir returns a defined Return node');

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
# SECTION 5: D1 constructive proof — if/else with branch+phi lowers correctly
# ---------------------------------------------------------------------------

subtest 'D1 constructive proof: if/else builds and lowers to 1 via lli' => sub {
    my ($d1_case) = grep { $_->{title} =~ /D1.*if.*else/i } @$cases;
    ok(defined $d1_case, 'D1 case found');

    my $ir_text = $d1_case->{ir} // '';
    my $return_node;
    eval { $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text) };
    ok(!$@, "D1 build_graph_from_ir does not croak (got: $@)")
        or diag("build error: $@");
    ok(defined $return_node, 'D1 build_graph_from_ir returns a defined Return node');

    my $verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
    is($verdict, 'GREEN', 'D1 ir block declares L: GREEN');

    if (defined $return_node) {
        my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
        ok(!$meta->{marked_unsupported}, 'D1 if/else graph is truly GREEN')
            or diag("gap: " . ($meta->{gap_reason} // 'none') . "\nerr: " . ($meta->{lower_error} // 'none'));

        my $ll = $meta->{ll_text} // '';
        unlike($ll, qr/Perl_/, 'D1 .ll: no Perl_ C-API symbols');
        unlike($ll, qr/\bSV\b/, 'D1 .ll: no SV type symbols');
        like($ll, qr/br i1/, 'D1 .ll: contains conditional branch (not just select)');
        like($ll, qr/phi i64/, 'D1 .ll: contains phi instruction');

        my $lli_out = $L->return_values->[0] // '';
        is($lli_out, '1', "D1 lli output is 1 (n=5, n>0 -> x=1)");
        is($lli_out, $d1_case->{_perl_actual} // '1',
            "D1 lli output matches perl oracle");
    }
};

# ---------------------------------------------------------------------------
# SECTION 6: Negative guard — a non-lowerable control-flow case claiming GREEN must FAIL
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

# ---------------------------------------------------------------------------
# SECTION 7: Per-case libperl-free assertion for every GREEN control-flow case
#
# All GREEN cases (D1-D7) must emit LLVM IR with NO Perl_/SV/sv_ symbols.
# D1 already had this assertion; D2-D7 were missing it (alignment gap).
# D8 is GAP (pure-GAP block, no emitted .ll to check).
# ---------------------------------------------------------------------------

subtest 'all GREEN control-flow cases emit libperl-free .ll' => sub {
    for my $case (@$cases) {
        my $title    = $case->{title};
        my $ir_text  = $case->{ir} // '';
        my $decl     = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);

        # Skip GAP cases — no .ll is emitted for them
        next if $decl eq 'GAP';

        my $return_node;
        eval { $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text) };
        next unless defined $return_node && !$@;

        my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
        my $ll = $meta->{ll_text} // '';

        SKIP: {
            skip "case '$title': no .ll emitted (GAP or lower failed)", 3
                unless length($ll) && !$meta->{marked_unsupported};

            unlike($ll, qr/Perl_/,   "case '$title': .ll has no Perl_ C-API symbols");
            unlike($ll, qr/\bSV\b/,  "case '$title': .ll has no SV type symbols");
            unlike($ll, qr/libperl/, "case '$title': .ll has no libperl references");
        }
    }
};

done_testing;
