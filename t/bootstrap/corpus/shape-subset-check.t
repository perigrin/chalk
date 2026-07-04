# ABOUTME: Tests MdtestCorpus::shape_subset_check — structural-subset match of a
# ABOUTME: case ir block (the spec) against a real graph (e.g. loaded from B::SoN).
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness::MdtestCorpus;

my $C = 'Chalk::CodeGen::Harness::MdtestCorpus';

# The spec: every node signature the ir block declares must exist in the real
# graph (kind, declared repr, Constant value, Coerce from/to). The real graph
# may contain MORE nodes (subset semantics) — B::SoN graphs carry pads,
# VarDecls, and control the hand-authored blocks omit.

my $SPEC = <<'END_IR';
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%add = Add(%c1, %c2) :Int
return %add
L: GREEN
END_IR

# Test 1: a graph built from the same block trivially matches.
{
    my $real = $C->build_graph_from_ir($SPEC);
    my $res  = $C->shape_subset_check($SPEC, $real);
    is($res->{verdict}, 'PASS', 'identical graph subset-matches its own spec')
        or diag(join('; ', ($res->{missing} // [])->@*));
    is_deeply($res->{missing}, [], 'nothing missing');
}

# Test 2: a real graph with EXTRA nodes still matches (subset semantics).
{
    my $bigger = <<'END_IR';
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%c9  = Constant(9) :Int
%add = Add(%c1, %c2) :Int
%mul = Multiply(%add, %c9) :Int
return %mul
END_IR
    my $spec_only_add = <<'END_IR';
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%add = Add(%c1, %c2) :Int
return %add
END_IR
    my $real = $C->build_graph_from_ir($bigger);
    my $res  = $C->shape_subset_check($spec_only_add, $real);
    is($res->{verdict}, 'PASS', 'spec is a subset of a bigger real graph');
}

# Test 3: a missing spec node is detected and named.
{
    my $real_small = $C->build_graph_from_ir(<<'END_IR');
%c1  = Constant(1) :Int
return %c1
END_IR
    my $res = $C->shape_subset_check($SPEC, $real_small);
    is($res->{verdict}, 'FAIL', 'missing Add node fails the subset match');
    ok((grep { /Add/ } $res->{missing}->@*), 'the missing node is named')
        or diag(join('; ', $res->{missing}->@*));
}

# Test 4: a repr mismatch on a matching kind is detected.
{
    my $real_num = $C->build_graph_from_ir(<<'END_IR');
%c3  = Constant(3) :Int
%c4  = Constant(4) :Int
%d3  = Coerce(%c3 : Int -> Num) :Num
%d4  = Coerce(%c4 : Int -> Num) :Num
%div = Divide(%d3, %d4) :Num
return %div
END_IR
    my $spec_int_div = <<'END_IR';
%d3  = Constant(3) :Int
%d4  = Constant(4) :Int
%div = Divide(%d3, %d4) :Int
return %div
END_IR
    my $res = $C->shape_subset_check($spec_int_div, $real_num);
    is($res->{verdict}, 'FAIL', 'Divide :Int spec does not match a :Num Divide');
}

# Test 5: a pure-GAP block (no node lines) passes trivially against any graph.
{
    my $real = $C->build_graph_from_ir($SPEC);
    my $res  = $C->shape_subset_check("L: GAP(not lowered)\n", $real);
    is($res->{verdict}, 'PASS', 'pure-GAP spec has no shape to enforce');
}

# Test 6: a node-line-free block that claims L: GREEN is a malformed spec, not
# a vacuous pass (I3 review: _is_pure_gap_block only checks node lines).
{
    my $real = $C->build_graph_from_ir($SPEC);
    my $res  = $C->shape_subset_check("L: GREEN\n", $real);
    is($res->{verdict}, 'SKIP', 'no-node-lines-but-not-GAP is SKIP, not a free PASS')
        or diag("verdict=$res->{verdict} reason=" . ($res->{reason} // ''));
}

# Test 7: greedy first-fit must not false-FAIL a satisfiable mixed-specificity
# spec. Two same-kind spec sigs (one strict :Int, one unconstrained repr) both
# have a valid real match; matching most-constrained-first is required so the
# lax sig does not consume the strict sig's only candidate. This mirrors the
# real B::SoN shape: a stamped node alongside an unstamped one of the same kind.
#
# The construction is deliberate (verified against greedy order): _sig_match on
# Add checks ONLY kind+repr (no value), so a lax Add (repr undef) and a strict
# Add (:Int) genuinely contend for the same real :Int Add. The DFS walk places
# the lax spec sigs before the strict one, and the real graph places its single
# :Int Add in the middle — so greedy first-fit lets a lax spec sig consume the
# one :Int Add the strict sig needed, reporting FAIL though the spec IS
# satisfiable. Distinct inputs keep the three Adds from hash-consing together.
# This test goes RED if the constrained-first sort is removed.
{
    # Real graph: two lax Adds (%top, %n) and ONE strict :Int Add (%m), with %m
    # in a middle DFS position (Return -> %top -> {%m, %n}).
    my $real = $C->build_graph_from_ir(<<'END_IR');
%a   = Constant(1)
%b   = Constant(2)
%c   = Constant(3)
%d   = Constant(4)
%m   = Add(%a, %b) :Int
%n   = Add(%c, %d)
%top = Add(%m, %n)
return %top
END_IR
    # Spec: two lax Adds (%s, %x) walked before the one strict Add (%y).
    my $spec = <<'END_IR';
%a = Constant(1)
%b = Constant(2)
%c = Constant(3)
%d = Constant(4)
%x = Add(%a, %b)
%y = Add(%c, %d) :Int
%s = Add(%x, %y)
return %s
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'PASS',
        'mixed-specificity same-kind spec matches (constrained-first, no false FAIL)')
        or diag('missing: ' . join('; ', ($res->{missing} // [])->@*));
}

# ---------------------------------------------------------------------------
# Fold-satisfaction (zhi 019f2a50): perl constant-folds literal arithmetic in
# op.c before B::SoN walks the optree, so `1 + 2` loads as a single
# Constant(3), not Add(Constant(1), Constant(2)). The corpus keeps the
# unfolded operation shape (it names the op under test), and the matcher
# learns that an arithmetic-op spec node over all-literal Constants is
# SATISFIED by a real Constant of the folded value + the op's declared repr.
# The subsumed operand Constants are satisfied by the fold too (they do not
# appear in the folded real graph). Chalk not folding is a known gap.
# ---------------------------------------------------------------------------

# The folded real graph, exactly as B::SoN emits it: one Constant.
sub folded_real ($value, $repr) {
    return $C->build_graph_from_ir("%r = Constant($value) :$repr\nreturn %r\n");
}

subtest 'Add over literals is satisfied by the folded Constant' => sub {
    my $spec = <<'END_IR';
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%add = Add(%c1, %c2) :Int
return %add
END_IR
    my $res = $C->shape_subset_check($spec, folded_real(3, 'Int'));
    is($res->{verdict}, 'PASS', 'Add(1,2):Int satisfied by Constant(3):Int')
        or diag('missing: ' . join('; ', ($res->{missing} // [])->@*));
};

subtest 'Subtract / Multiply / Modulo over literals fold' => sub {
    my %cases = (
        'Subtract' => ['%c1 = Constant(5) :Int' . "\n" . '%c2 = Constant(3) :Int' . "\n" . '%o = Subtract(%c1, %c2) :Int', 2, 'Int'],
        'Multiply' => ['%c1 = Constant(3) :Int' . "\n" . '%c2 = Constant(4) :Int' . "\n" . '%o = Multiply(%c1, %c2) :Int', 12, 'Int'],
        'Modulo'   => ['%c1 = Constant(-7) :Int' . "\n" . '%c2 = Constant(3) :Int' . "\n" . '%o = Modulo(%c1, %c2) :Int', 2, 'Int'],
    );
    for my $op (sort keys %cases) {
        my ($nodes, $val, $repr) = $cases{$op}->@*;
        my $spec = "$nodes\nreturn %o\n";
        my $res = $C->shape_subset_check($spec, folded_real($val, $repr));
        is($res->{verdict}, 'PASS', "$op over literals -> Constant($val):$repr")
            or diag('missing: ' . join('; ', ($res->{missing} // [])->@*));
    }
};

subtest 'Divide over literals folds through Coerce to a Num Constant' => sub {
    # The Float division corpus shape: Coerce(Int->Num) on each operand.
    my $spec = <<'END_IR';
%c3  = Constant(3) :Int
%c4  = Constant(4) :Int
%d3  = Coerce(%c3 : Int -> Num) :Num
%d4  = Coerce(%c4 : Int -> Num) :Num
%div = Divide(%d3, %d4) :Num
return %div
END_IR
    my $res = $C->shape_subset_check($spec, folded_real('0.75', 'Num'));
    is($res->{verdict}, 'PASS', 'Divide(3,4):Num satisfied by Constant(0.75):Num')
        or diag('missing: ' . join('; ', ($res->{missing} // [])->@*));
};

subtest 'a WRONG folded value still FAILs (fold is checked, not assumed)' => sub {
    my $spec = <<'END_IR';
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%add = Add(%c1, %c2) :Int
return %add
END_IR
    # Real graph folds to the wrong constant (4, not 3).
    my $res = $C->shape_subset_check($spec, folded_real(4, 'Int'));
    is($res->{verdict}, 'FAIL', 'Add(1,2) is NOT satisfied by Constant(4)');
};

subtest 'an op whose direct input is a non-literal does not fold-match' => sub {
    # Outer Add's first operand is an Add node, not a literal Constant. Only a
    # DIRECT-all-literals op folds (matching the corpus's single-op arithmetic
    # cases); a nested op is not fold-collapsed, so a bare folded Constant must
    # NOT satisfy it. (Recursive folding of nested literal trees is out of
    # scope — no corpus case needs it.)
    my $spec = <<'END_IR';
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%i   = Add(%c1, %c2) :Int
%c3  = Constant(3) :Int
%o   = Add(%i, %c3) :Int
return %o
END_IR
    my $res = $C->shape_subset_check($spec, folded_real(6, 'Int'));
    is($res->{verdict}, 'FAIL',
        'a nested Add is not fold-satisfied by a single folded Constant');
};

subtest 'literal comparison folds to a Bool Constant (statements 1<2)' => sub {
    # perl folds `1 < 2` to a boolean in op.c; B::SoN emits Constant(1):Boolean
    # for true and Constant():Boolean (empty string) for false.
    my $true_spec = <<'END_IR';
%one = Constant(1) :Int
%two = Constant(2) :Int
%cmp = NumLt(%one, %two) :Bool
return %cmp
END_IR
    my $rt = $C->shape_subset_check($true_spec, folded_real(1, 'Bool'));
    is($rt->{verdict}, 'PASS', 'NumLt(1,2):Bool satisfied by Constant(1):Bool')
        or diag('missing: ' . join('; ', ($rt->{missing} // [])->@*));

    my $false_spec = <<'END_IR';
%two = Constant(2) :Int
%one = Constant(1) :Int
%cmp = NumLt(%two, %one) :Bool
return %cmp
END_IR
    # false folds to the empty-string Bool constant.
    my $real_false = $C->build_graph_from_ir("%r = Constant() :Bool\nreturn %r\n");
    my $rf = $C->shape_subset_check($false_spec, $real_false);
    is($rf->{verdict}, 'PASS', 'NumLt(2,1):Bool satisfied by Constant():Bool')
        or diag('missing: ' . join('; ', ($rf->{missing} // [])->@*));
};

subtest 'a fold operand still required by another consumer is NOT over-satisfied' => sub {
    # Constant(2) is a fold operand of Add(2,3) AND a LIVE operand of a Coerce
    # that itself feeds the returned top Add — so the Coerce (and thus its
    # Constant(2) input) is reachable. The real graph has the inner fold result
    # Constant(5) and a top Add + Coerce, but NO standalone Constant(2). The
    # fold subsumes the inner Add (and Constant(3), its sole consumer), but
    # Constant(2) has a non-fold consumer (the Coerce), so it must survive as a
    # requirement — absent in the real graph, this must FAIL. An id-set skip
    # that dropped Constant(2) for all consumers would false-PASS.
    my $spec = <<'END_IR';
%c2  = Constant(2) :Int
%c3  = Constant(3) :Int
%add = Add(%c2, %c3) :Int
%cd  = Coerce(%c2 : Int -> Num) :Num
%top = Add(%add, %cd) :Int
return %top
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%five = Constant(5) :Int
%c9   = Constant(9) :Int
%cd   = Coerce(%c9 : Int -> Num) :Num
%top  = Add(%five, %cd) :Int
return %top
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'FAIL',
        'shared fold operand still required by a live Coerce is not over-satisfied')
        or diag('missing: ' . join('; ', ($res->{missing} // [])->@*));
};

subtest 'a non-numeric literal under an arithmetic op does not fold (no warn, no false PASS)' => sub {
    # Add(Constant("foo"):Str, Constant(2):Int) must NOT fold: perl would coerce
    # "foo" to 0 with a warning and spuriously match Constant(2). The fold gate
    # requires numeric operand reprs. (Review finding: repr-blind fold.)
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };
    my $spec = <<'END_IR';
%s   = Constant("foo") :Str
%c   = Constant(2) :Int
%add = Add(%s, %c) :Int
return %add
END_IR
    my $res = $C->shape_subset_check($spec, folded_real(2, 'Int'));
    is($res->{verdict}, 'FAIL',
        'Str "foo" operand is not fold-coerced into a numeric match');
    is(scalar(@warnings), 0, 'no numeric-coercion warning leaked to STDERR')
        or diag("warnings: @warnings");
};

subtest 'the unfolded shape still matches an unfolded real graph (Chalk path)' => sub {
    # Fold-satisfaction is additive: a producer that does NOT fold (Chalk)
    # still matches the literal spec directly.
    my $spec = <<'END_IR';
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%add = Add(%c1, %c2) :Int
return %add
END_IR
    my $real = $C->build_graph_from_ir($spec);
    my $res  = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'PASS', 'unfolded spec still matches an unfolded real graph');
};

done_testing();
