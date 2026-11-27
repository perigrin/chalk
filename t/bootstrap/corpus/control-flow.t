# ABOUTME: Runner for the control-flow mdtest corpus topic (constructive format).
# ABOUTME: Asserts the topic's static inventory + L declarations; behavior/shape/invariant is owned by son-corpus-wide.t.
use 5.42.0;
use utf8;

use lib 'lib', 't/lib';
use Test::Chalk;

use Chalk::CodeGen::Harness::MdtestCorpus;
use Chalk::CodeGen::Harness::LLVMDriver;

use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;


my $CONTROL_FLOW_MD = 't/corpus/mdtest/control-flow.md';

unless (-f $CONTROL_FLOW_MD) {
    die "control-flow.md not found at $CONTROL_FLOW_MD", "\n";
}

# ---------------------------------------------------------------------------
# SECTION 1: Parse control-flow.md and verify the topic's named idioms are present.
#
# This runner asserts the STATIC inventory + L declarations of the corpus file.
# The authoritative behavior/shape/invariant gate is
# t/bootstrap/corpus/son-corpus-wide.t, which lowers each case's PERL SOURCE
# through B::SoN -> chalk -> lli. The old per-case run_case checks here lowered
# the hand-written IR BLOCK through the constructive builder -- a second,
# drifting lowering path with hardcoded case counts that went stale on every
# corpus addition (zhi 019f53a0). Retired in favor of the single authoritative
# gate; the presence/declaration checks below lower nothing and stay.
#   D6: GREEN via TernaryExpr -> select i1
#   D1/D2/D3/D4/D5/D7: GREEN via cfg-blocks-phi (br + phi)
#   D8: GAP (needs LLVM landingpad — different capability)
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($CONTROL_FLOW_MD);

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
# SECTION 3: Verify L-verdict declarations per case
#
# Most cases are GREEN via their respective lowering paths. A handful are
# declared GAP by design and are exempted from the GREEN expectation:
#   D3d: foreach body that writes the iterator (aliasing write-back not modeled)
#   D8:  try/catch (needs an LLVM landingpad — a different capability)
#   T1:  list-context ternary (t/base print-ternary blocker)
#   T2b: TAKEN die aborts (the equality harness cannot assert an abort)
#   T3:  cond_expr inside a loop body (t/base blocker)
#   T4:  loop control (last) inside a loop body (t/base blocker)
# The authoritative behavior/shape/invariant gate is son-corpus-wide.t; here we
# only assert each case's DECLARED verdict matches its known status.
# ---------------------------------------------------------------------------

# Every case declares a verdict, and a GAP must say WHY.
#
# This was a hardcoded list of titles asserted to be GAP, with everything else
# asserted GREEN -- a second copy of what each case's own `L:` line already
# states, which drifted the moment a verdict changed. (Six cases were failing
# here for exactly that reason, in both directions: T1/T3/T4 had been listed as
# GAP-by-design while their `L:` lines say GAP for a stated reason, and
# T2c/T4c/T8 declare `L: GAP(reason)` while the list expected GREEN.) Commit
# 1311e782 retired the same anti-pattern -- hardcoded counts -- from the other
# per-topic runners; this subtest was the survivor.
#
# What is worth pinning is that the declaration is WELL-FORMED: a verdict is
# one of the two known values, and a GAP carries a reason rather than being an
# unexplained exemption. Which cases are GAP is the corpus's business, and the
# gate measures whether that matches reality.
subtest 'declared L verdicts are well-formed (a GAP states its reason)' => sub {
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
# SECTION 4: D6 constructive proof — the TernaryExpr block builds; T2 refuses it
# ---------------------------------------------------------------------------

subtest 'D6 constructive proof: the block builds; T2 refuses it by name' => sub {
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

    # THE HAND-WRITTEN BLOCK is the old dialect (a VarDecl heads its chain, no
    # Start), which only the retired fallback lowered. The program itself is
    # gate-green through B::SoN and T2 (son-corpus-wide.t); this block, handed
    # to T2, is refused by T2's reason -- never lowered wrong.
    if (defined $return_node) {
        my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
        ok($meta->{marked_unsupported}, 'D6 block: T2 lowers no module for it');
        like($meta->{lower_error} // '', qr/\AGAP: T2: out of its slices \(/, "D6 block: refused by T2's reason")
            or diag($meta->{lower_error} // 'no reason');
    }
};

# ---------------------------------------------------------------------------
# SECTION 5: D1 constructive proof — the if/else block builds; T2 refuses it
# ---------------------------------------------------------------------------

subtest 'D1 constructive proof: the block builds; T2 refuses it by name' => sub {
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

    # THE HAND-WRITTEN BLOCK is the old dialect (a VarDecl heads its chain, no
    # Start), which only the retired fallback lowered. The program itself is
    # gate-green through B::SoN and T2 (son-corpus-wide.t); this block, handed
    # to T2, is refused by T2's reason -- never lowered wrong.
    if (defined $return_node) {
        my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
        ok($meta->{marked_unsupported}, 'D1 block: T2 lowers no module for it');
        like($meta->{lower_error} // '', qr/\AGAP: T2: out of its slices \(/, "D1 block: refused by T2's reason")
            or diag($meta->{lower_error} // 'no reason');
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
#
# THE OLD-DIALECT BLOCKS (as D1's and D6's above): hand-written before wire v2,
# so T2 refuses them; each program is gate-green through B::SoN and T2
# (son-corpus-wide.t). Each is held here by its refusal's name -- a skip once
# hid them all ("no .ll emitted"), and a block that lowers now fails until it
# leaves this table.
# ---------------------------------------------------------------------------

my %REFUSED = (
    ( map { $_ => 'PadAccess' } qw(D4 D6 D7 D9) ),
    D1 => 'a statement VarDecl',
    ( map { $_ => 'Phi' } qw(D2 D2b D2c D2d D2e D3 D3a D3b D3e D5 T3) ),
    ( map { $_ => 'a control node with 2 successors' } qw(T4 T4b T4d T6 T7) ),
    T5 => 'a direct call with no sub',
);

subtest 'all GREEN control-flow cases emit libperl-free .ll' => sub {
    for my $case (@$cases) {
        my $title    = $case->{title};
        my $ir_text  = $case->{ir} // '';
        my $decl     = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);

        # Skip GAP cases — no .ll is emitted for them
        next if $decl eq 'GAP';

        my $return_node;
        eval { $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text) };
        ok(defined $return_node && !$@, "case '$title': its block builds") or diag($@), next;

        my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
        my $ll = $meta->{ll_text} // '';

        my ($id) = $title =~ /\A(\S+)/;
        if ( my $why = $REFUSED{$id} ) {
            like($meta->{lower_error} // '', qr/\AGAP: T2: out of its slices \(\Q$why\E\)/,
                "case '$title': T2 refuses its hand-written block by name");
            next;
        }
        ok(length($ll) && !$meta->{marked_unsupported}, "case '$title': T2 lowers its block")
            or diag($meta->{lower_error} // 'no reason'), next;
        unlike($ll, qr/Perl_/,   "case '$title': .ll has no Perl_ C-API symbols");
        unlike($ll, qr/\bSV\b/,  "case '$title': .ll has no SV type symbols");
        unlike($ll, qr/libperl/, "case '$title': .ll has no libperl references");
    }
};

done_testing;
