# ABOUTME: Runner for the logical-operators mdtest corpus topic (constructive format).
# ABOUTME: L1 (&&), L2 (||), L3 (//), L3b (undef-left //), L4 (!) are all GREEN.
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
# All 5 logical idioms (L1-L4 + L3b) must be present.
#   L1  (&&):  GREEN — cfg-blocks-phi lands And lowering (branch+phi)
#   L2  (||):  GREEN — cfg-blocks-phi lands Or lowering (branch+phi)
#   L3  (//):  GREEN — DefinedOr with Int-typed LHS (always defined); Undef repr + definedness branch
#   L3b (//):  GREEN — DefinedOr with Undef-typed LHS (runtime-undef via alloca+store+load)
#   L4  (!):   GREEN — Bool repr (i1) + Not (xor i1) + Coerce(Int->Bool) + type-tagged return
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($LOGICAL_MD);
is(scalar(@$cases), 5, 'logical.md has 5 cases (L1-L4 + L3b)');

my @titles = map { $_->{title} } @$cases;
ok((grep { /L1.*logical.*and/i       } @titles), 'case: L1 logical and present');
ok((grep { /L2.*logical.*or/i        } @titles), 'case: L2 logical or present');
ok((grep { /L3.*defined.*or/i        } @titles), 'case: L3 defined-or present');
ok((grep { /L3b.*defined.*or.*undef/i} @titles), 'case: L3b defined-or undef-left present');
ok((grep { /L4.*not/i                } @titles), 'case: L4 not present');

# ---------------------------------------------------------------------------
# SECTION 2: Run all 5 cases end-to-end
#
# For each case:
#   - behavior check must PASS (perl oracle vs declared return value)
#   - ir-shape check must not FAIL (pure-GAP blocks trivially pass)
#   - L-verdict check must PASS (declared verdict matches actual verdict)
#
# All 5 cases declare L: GREEN.
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
# All 5 cases declare L: GREEN:
#   L1  (&&):  GREEN — And lowering via branch+phi
#   L2  (||):  GREEN — Or lowering via branch+phi
#   L3  (//):  GREEN — DefinedOr via Undef representation + definedness branch+phi
#   L3b (//):  GREEN — DefinedOr undef-left path (runtime-undef via alloca+store+load)
#   L4  (!):   GREEN — Bool repr + Not + Coerce(Int->Bool) + type-tagged Bool return
# ---------------------------------------------------------------------------

subtest 'All 5 cases declare L: GREEN' => sub {
    plan tests => 5;
    for my $case (@$cases) {
        my $ir_text = $case->{ir} // '';
        my $decl    = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        my $title   = $case->{title};
        is($decl, 'GREEN', "case '$title': declared L: GREEN");
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
        is($lli_out, 'Int:7', "L1 lli output is Int:7 (3&&7 == 7, type-tagged)");
        is($lli_out, $l1_case->{_perl_actual} // 'Int:7',
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
        is($lli_out, 'Int:3', "L2 lli output is Int:3 (3||7 == 3, type-tagged)");
        is($lli_out, $l2_case->{_perl_actual} // 'Int:3',
            "L2 lli output matches perl oracle");
    }
};

subtest 'L3, L3b, L4 all build graphs (all are GREEN)' => sub {
    plan tests => 3;
    # L3 (//) now has a buildable graph (DefinedOr with Int LHS).
    my ($l3_case) = grep { $_->{title} =~ /^L3 / } @$cases;
    if (defined $l3_case) {
        my $ir_text = $l3_case->{ir} // '';
        my $return_node;
        eval { $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text) };
        ok(defined $return_node && !$@,
            "case '$l3_case->{title}': build_graph_from_ir returns a node (GREEN, DefinedOr lowers)");
    }
    # L3b (// undef-left) has a buildable graph (DefinedOr with Undef LHS).
    my ($l3b_case) = grep { $_->{title} =~ /L3b/ } @$cases;
    if (defined $l3b_case) {
        my $ir_text = $l3b_case->{ir} // '';
        my $return_node;
        eval { $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text) };
        ok(defined $return_node && !$@,
            "case '$l3b_case->{title}': build_graph_from_ir returns a node (GREEN, undef-left lowers)");
    }
    # L4 (!) now has a buildable graph (Not + Coerce Bool).
    my ($l4_case) = grep { $_->{title} =~ /L4.*not/i } @$cases;
    if (defined $l4_case) {
        my $ir_text = $l4_case->{ir} // '';
        my $return_node;
        eval { $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text) };
        ok(defined $return_node && !$@,
            "case '$l4_case->{title}': build_graph_from_ir returns a node (GREEN, Not lowers)");
    }
};

# ---------------------------------------------------------------------------
# SECTION 5: L3 constructive proofs — DefinedOr builds and lowers correctly
#
# L3 (defined-left => 3, Int:3): DefinedOr with Int-typed LHS.
# L3b (undef-left => 7, Int:7): DefinedOr with Undef-typed LHS (runtime-undef).
#
# Both must: lli==perl, .ll libperl-free, structure contains branch+phi.
# L3b must additionally: .ll contains alloca+store+load (runtime-undef,
# not constant-foldable by LLVM optimizer).
# ---------------------------------------------------------------------------

subtest 'L3 constructive proof: DefinedOr(Int,Int) builds and lowers to 3 via lli' => sub {
    my ($l3_case) = grep { $_->{title} =~ /^L3 / } @$cases;
    ok(defined $l3_case, 'L3 case found');

    my $ir_text = $l3_case->{ir} // '';
    my $return_node;
    eval { $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text) };
    ok(!$@, "L3 build_graph_from_ir does not croak (got: $@)")
        or diag("build error: $@");
    ok(defined $return_node, 'L3 build_graph_from_ir returns a defined Return node');

    my $verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
    is($verdict, 'GREEN', 'L3 ir block declares L: GREEN');

    if (defined $return_node) {
        my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
        ok(!$meta->{marked_unsupported}, 'L3 DefinedOr graph is truly GREEN (not marked_unsupported)')
            or diag("gap reason: " . ($meta->{gap_reason} // 'none') . "\nerror: " . ($meta->{lower_error} // 'none'));

        # Libperl-free assertion.
        my $ll = $meta->{ll_text} // '';
        unlike($ll, qr/Perl_/, 'L3 .ll: no Perl_ C-API symbols');
        unlike($ll, qr/\bSV\b/, 'L3 .ll: no SV type symbols');
        unlike($ll, qr/sv_/,    'L3 .ll: no sv_ C-API symbols');
        unlike($ll, qr/libperl/,'L3 .ll: no libperl reference');

        my $lli_out = $L->return_values->[0] // '';
        is($lli_out, 'Int:3', "L3 lli output is Int:3 (3//7 == 3, left is defined)");
        is($lli_out, $l3_case->{_perl_actual} // 'Int:3',
            "L3 lli output matches perl oracle");

        # Structural sanity: .ll contains the definedness branch.
        like($ll, qr/br i1/, 'L3 .ll: contains br i1 (definedness branch)');
        like($ll, qr/phi i64/, 'L3 .ll: contains phi i64 (operand-selecting merge)');
    }
};

subtest 'L3b constructive proof: DefinedOr(Undef,Int) builds and lowers to 7 via lli' => sub {
    my ($l3b_case) = grep { $_->{title} =~ /L3b/ } @$cases;
    ok(defined $l3b_case, 'L3b case found');

    my $ir_text = $l3b_case->{ir} // '';
    my $return_node;
    eval { $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text) };
    ok(!$@, "L3b build_graph_from_ir does not croak (got: $@)")
        or diag("build error: $@");
    ok(defined $return_node, 'L3b build_graph_from_ir returns a defined Return node');

    my $verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
    is($verdict, 'GREEN', 'L3b ir block declares L: GREEN');

    if (defined $return_node) {
        my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
        ok(!$meta->{marked_unsupported}, 'L3b DefinedOr(Undef) graph is truly GREEN (not marked_unsupported)')
            or diag("gap reason: " . ($meta->{gap_reason} // 'none') . "\nerror: " . ($meta->{lower_error} // 'none'));

        # Libperl-free assertion.
        my $ll = $meta->{ll_text} // '';
        unlike($ll, qr/Perl_/, 'L3b .ll: no Perl_ C-API symbols');
        unlike($ll, qr/\bSV\b/, 'L3b .ll: no SV type symbols');
        unlike($ll, qr/sv_/,    'L3b .ll: no sv_ C-API symbols');
        unlike($ll, qr/libperl/,'L3b .ll: no libperl reference');

        my $lli_out = $L->return_values->[0] // '';
        is($lli_out, 'Int:7', "L3b lli output is Int:7 (undef//7 == 7, right operand)");
        is($lli_out, $l3b_case->{_perl_actual} // 'Int:7',
            "L3b lli output matches perl oracle");

        # Runtime-undef guard: .ll must use alloca+store+load for the defined bit.
        # This prevents LLVM from constant-folding the branch even with optimizations.
        like($ll, qr/alloca/,   'L3b .ll: contains alloca (runtime-opaque defined bit)');
        like($ll, qr/store i1/, 'L3b .ll: contains store i1 (defined bit written to alloca)');
        like($ll, qr/load i1/,  'L3b .ll: contains load i1 (defined bit read at runtime)');

        # Structural sanity: definedness branch present.
        like($ll, qr/br i1/,    'L3b .ll: contains br i1 (definedness branch)');
        like($ll, qr/phi i64/,  'L3b .ll: contains phi i64 (operand-selecting merge)');
    }
};

# ---------------------------------------------------------------------------
# SECTION 6: L4 constructive proof — Not(Bool) builds and lowers correctly
#
# !5 => false (Bool:). The ir-block uses Coerce(Int->Bool) for truthiness then
# Not (xor i1 %cond, true). lli output must match the type-tagged perl oracle.
# ---------------------------------------------------------------------------


subtest 'L4 constructive proof: Not builds and lowers to Bool: (false) via lli' => sub {
    my ($l4_case) = grep { $_->{title} =~ /L4.*not/i } @$cases;
    ok(defined $l4_case, 'L4 case found');

    my $ir_text = $l4_case->{ir} // '';
    my $return_node;
    eval { $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text) };
    ok(!$@, "L4 build_graph_from_ir does not croak (got: $@)")
        or diag("build error: $@");
    ok(defined $return_node, 'L4 build_graph_from_ir returns a defined Return node');

    my $verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
    is($verdict, 'GREEN', 'L4 ir block declares L: GREEN');

    if (defined $return_node) {
        my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
        ok(!$meta->{marked_unsupported}, 'L4 Not graph is truly GREEN (not marked_unsupported)')
            or diag("gap reason: " . ($meta->{gap_reason} // 'none') . "\nerror: " . ($meta->{lower_error} // 'none'));

        # Libperl-free assertion: the emitted .ll must not call any Perl C-API.
        my $ll = $meta->{ll_text} // '';
        unlike($ll, qr/Perl_/, 'L4 .ll: no Perl_ C-API symbols');
        unlike($ll, qr/\bSV\b/, 'L4 .ll: no SV type symbols');
        unlike($ll, qr/sv_/,    'L4 .ll: no sv_ C-API symbols');
        unlike($ll, qr/libperl/,'L4 .ll: no libperl reference');

        # Bool: (false) — type-tagged. NOT "Int:0" (wrong type) or "Str:" (wrong identity).
        my $lli_out = $L->return_values->[0] // '';
        is($lli_out, 'Bool:', "L4 lli output is Bool: (false, type-tagged)");
        is($lli_out, $l4_case->{_perl_actual} // 'Bool:',
            "L4 lli output matches perl oracle");

        # Structural sanity: .ll contains xor i1 (Not instruction).
        like($ll, qr/xor i1/, 'L4 .ll: contains xor i1 (Not lowering)');
        # .ll contains icmp ne (truthiness coercion from Int).
        like($ll, qr/icmp ne/, 'L4 .ll: contains icmp ne (Int->Bool truthiness)');
    }
};

# ---------------------------------------------------------------------------
# SECTION 7: Negative guard — a logical case claiming L: GREEN must FAIL
# if the ir block has no buildable nodes (pure-GAP with GREEN claim).
# ---------------------------------------------------------------------------

subtest 'guard: pure-GAP block with L: GREEN for logical op FAILS L-verdict' => sub {
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
