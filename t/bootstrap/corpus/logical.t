# ABOUTME: Runner for the logical-operators mdtest corpus topic (constructive format).
# ABOUTME: Asserts the topic's static inventory + L declarations; behavior/shape/invariant is owned by son-corpus-wide.t.
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
# SECTION 1: Parse logical.md and verify the topic's named idioms are present.
#
# This runner asserts the STATIC inventory + L declarations of the corpus file.
# The authoritative behavior/shape/invariant gate is
# t/bootstrap/corpus/son-corpus-wide.t, which lowers each case's PERL SOURCE
# through B::SoN -> chalk -> lli. The old per-case run_case checks here lowered
# the hand-written IR BLOCK through the constructive builder -- a second,
# drifting lowering path with hardcoded case counts that went stale on every
# corpus addition, and it could not build the L3c early-return single-exit shape
# that son-corpus-wide.t gates GREEN (zhi 019f53a0). Retired in favor of the
# single authoritative gate; the presence/declaration checks below lower nothing
# and stay.
#   L1  (&&):  GREEN — cfg-blocks-phi lands And lowering (branch+phi)
#   L2  (||):  GREEN — cfg-blocks-phi lands Or lowering (branch+phi)
#   L3  (//):  GREEN — DefinedOr with Int-typed LHS (always defined); Undef repr + definedness branch
#   L3b (//):  GREEN — DefinedOr with Undef-typed LHS (runtime-undef via alloca+store+load)
#   L4  (!):   GREEN — Boolean repr (i1) + Not (xor i1) + Coerce(Int->Boolean) + type-tagged return
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($LOGICAL_MD);

my @titles = map { $_->{title} } @$cases;
ok((grep { /L1.*logical.*and/i       } @titles), 'case: L1 logical and present');
ok((grep { /L2.*logical.*or/i        } @titles), 'case: L2 logical or present');
ok((grep { /L3.*defined.*or/i        } @titles), 'case: L3 defined-or present');
ok((grep { /L3b.*defined.*or.*undef/i} @titles), 'case: L3b defined-or undef-left present');
ok((grep { /L3c.*early.return/i      } @titles), 'case: L3c defined-or early-return present');
ok((grep { /L4.*not/i                } @titles), 'case: L4 not present');

# ---------------------------------------------------------------------------
# SECTION 3: Verify L-verdict declarations per case
#
# What the 5 named cases declare:
#   L1  (&&):  GREEN — And lowering via branch+phi
#   L2  (||):  GREEN — Or lowering via branch+phi
#   L3  (//):  GREEN — DefinedOr via Undef representation + definedness branch+phi
#   L3b (//):  GREEN — was a D2 GAP (the merge is Scalar: Undef joined with Int,
#                     with no machine encoding); restored by 35e32314.
#   L4  (!):   GREEN — Boolean repr + Not + Coerce(Int->Boolean) + type-tagged Boolean return
# ---------------------------------------------------------------------------

# THE LIST IS EMPTY, AND THAT IS THE POINT OF IT.
#
# It held three D2 GAPs -- L3b, L3c, L3d -- from the ruling (D2, 2026-08-26)
# that a merge of `Undef` with a defined arm is `Scalar`, the correct least
# upper bound of two siblings, and that `Scalar` having no machine encoding was
# a temporary drop worth taking because `Int` was the WRONG answer for a value
# that is undef on one path.
#
# All three were restored to GREEN by commit 35e32314 ("L3b/L3c/L3d promoted;
# the floor is 220, past the 218 it fell from"), and this list was not updated
# -- so the test failed, which is EXACTLY what it was built to do. Its original
# note: "this list going stale must FAIL the test rather than quietly absorb a
# new GAP. Restoring these to GREEN is T2's acceptance criterion."
#
# The criterion was met and the acknowledgement is this edit. The mechanism
# stays: it is NAMED rather than pattern-matched, so a FOURTH case GAPping here
# is a regression rather than more of the same, and an empty list makes any GAP
# in this file a failure.
my %DECLARED_GAP;

subtest 'every case declares the L: verdict it is supposed to' => sub {
    plan tests => scalar @$cases;
    for my $case (@$cases) {
        my $ir_text = $case->{ir} // '';
        my $decl    = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        my $title   = $case->{title};
        my $want    = $DECLARED_GAP{$title} ? 'GAP' : 'GREEN';
        is($decl, $want, "case '$title': declared L: $want");
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
        is($lli_out, '7', "L1 lli prints 7 (3&&7 == 7)");
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
        is($lli_out, '3', "L2 lli prints 3 (3||7 == 3)");
        is($lli_out, $l2_case->{_perl_actual} // '3',
            "L2 lli output matches perl oracle");
    }
};

# Buildability only -- a graph being well-formed is a separate question from
# whether the backend can encode it. L3b BUILDS but is a declared GAP (D2): the
# merge is Scalar, which has no machine encoding until T2.
subtest 'L3, L3b, L4 all build graphs' => sub {
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
            "case '$l3b_case->{title}': build_graph_from_ir returns a node (builds; GAP only at the encoding)");
    }
    # L4 (!) now has a buildable graph (Not + Coerce Boolean).
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
        is($lli_out, '3', "L3 lli prints 3 (3//7 == 3, left is defined)");
        is($lli_out, $l3_case->{_perl_actual} // '3',
            "L3 lli output matches perl oracle");

        # Structural sanity: .ll contains the definedness branch.
        like($ll, qr/br i1/, 'L3 .ll: contains br i1 (definedness branch)');
        like($ll, qr/phi i64/, 'L3 .ll: contains phi i64 (operand-selecting merge)');
    }
};

# L3b IS A LOWERING PROOF AGAIN, which is the revert this block predicted.
#
# It became a GAP under the D2 ruling: the merge of an Undef arm with a defined
# arm is `Scalar`, and `Scalar` had no machine encoding. The subtest inverted
# to pin the refusal, with the note "When T2 lands, this reverts to the
# lowering proof it was."
#
# The condition it was waiting on has been met by a different route than
# expected: `Scalar` acquired a machine type (%Slot, the tagged cell) rather
# than T2 narrowing it away, so the case was promoted back to GREEN by a340d22a
# and the corpus prose records the promotion. The refusal it pinned --
# "DefinedOr with repr=Scalar reached LLVM backend" -- no longer exists, and a
# test asserting a refusal that cannot happen is a false RED.
#
# So it reverts. `undef // 7` is 7, and the interesting part is that the result
# is still typed `Scalar`: at runtime the maybe-ness is discharged, but the
# STATIC type is the join of the two arms and the phi needs one machine type
# for both, so the narrower arm is boxed.
subtest 'L3b lowering proof: DefinedOr(Undef,Int) builds and lowers to 7' => sub {
    my ($l3b_case) = grep { $_->{title} =~ /L3b/ } @$cases;
    ok(defined $l3b_case, 'L3b case found');

    my $ir_text = $l3b_case->{ir} // '';
    my $return_node;
    eval { $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text) };
    ok(!$@, "L3b build_graph_from_ir does not croak (got: $@)")
        or diag("build error: $@");
    ok(defined $return_node, 'L3b builds');

    my $verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
    is($verdict, 'GREEN', 'L3b ir block declares L: GREEN (promoted by a340d22a)');

    # The join is still Scalar, and the ir block must still say so. THAT part
    # of the D2 ruling did not change -- only whether Scalar can be lowered.
    like($ir_text, qr/DefinedOr\([^)]*\) :Scalar/,
        'L3b ir block still pins the merge at :Scalar -- Undef and Int are siblings under it');

    if (defined $return_node) {
        my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);

        ok(!$meta->{marked_unsupported},
            'L3b lowering SUCCEEDS -- Scalar has a machine type (%Slot) now')
            or diag('lower error: ' . ($meta->{lower_error} // '(none)'));
    }
};

# ---------------------------------------------------------------------------
# SECTION 6: L4 constructive proof — Not(Boolean) builds and lowers correctly
#
# !5 => false (Bool:). The ir-block uses Coerce(Int->Boolean) for truthiness then
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
        is($lli_out, '', "L4 lli prints the empty string for false (false)");
        is($lli_out, $l4_case->{_perl_actual} // '',
            "L4 lli output matches perl oracle");

        # Structural sanity: .ll contains xor i1 (Not instruction).
        like($ll, qr/xor i1/, 'L4 .ll: contains xor i1 (Not lowering)');
        # .ll contains icmp ne (truthiness coercion from Int).
        like($ll, qr/icmp ne/, 'L4 .ll: contains icmp ne (Int->Boolean truthiness)');
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
