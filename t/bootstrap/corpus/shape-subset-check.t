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

# ---------------------------------------------------------------------------
# Propagation-satisfaction (zhi 019f2a50): perl's optree copy/const-propagates
# lexical pads away before B::SoN walks, so `my $x = 1; $x` loads as just
# Constant(1) — no VarDecl/PadAccess/name-Constant. The corpus keeps the
# pad-explicit shape (it names the lexical idiom); the matcher treats a spec
# VarDecl+PadAccess read chain as satisfied when the value the VarDecl binds is
# present in the real graph (the pad was propagated). The scaffolding
# (name-Constant, VarDecl, PadAccess) is subsumed; the value stays required.
# A non-propagating producer (Chalk) still matches the pad-explicit shape.
# ---------------------------------------------------------------------------

subtest 'a propagated pad (my $x = 1; $x) is satisfied by the value directly (A1)' => sub {
    # Spec: full pad scaffolding. Real: just Constant(1) (pad propagated away).
    my $spec = <<'END_IR';
%one  = Constant(1) :Int
%xn   = Constant("$x") :Str
%vx   = VarDecl(%xn, %one) :Int
%rx   = PadAccess(%vx, "$x") :Int
return %rx
control: %vx
END_IR
    my $real = $C->build_graph_from_ir("%r = Constant(1) :Int\nreturn %r\n");
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'PASS', 'pad scaffolding subsumed; Constant(1) matches')
        or diag('missing: ' . join('; ', ($res->{missing} // [])->@*));
};

subtest 'a propagated pad over a computed select (D6 ternary) matches the value graph' => sub {
    # Spec: NumGt + TernaryExpr + pad scaffolding. Real (B::SoN): the select
    # value graph with the pad propagated away.
    my $spec = <<'END_IR';
%n    = Constant(5) :Int
%zero = Constant(0) :Int
%cmp  = NumGt(%n, %zero) :Bool
%c1   = Constant(1) :Int
%c2   = Constant(2) :Int
%tern = TernaryExpr(%cmp, %c1, %c2) :Int
%xn   = Constant("$x") :Str
%vx   = VarDecl(%xn, %tern) :Int
%rx   = PadAccess(%vx, "$x") :Int
return %rx
control: %vx
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%n    = Constant(5) :Int
%zero = Constant(0) :Int
%cmp  = NumGt(%n, %zero) :Bool
%c1   = Constant(1) :Int
%c2   = Constant(2) :Int
%tern = TernaryExpr(%cmp, %c1, %c2) :Int
return %tern
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'PASS', 'pad subsumed; the NumGt/TernaryExpr core matches')
        or diag('missing: ' . join('; ', ($res->{missing} // [])->@*));
};

subtest 'propagation does not subsume the value node itself (still required)' => sub {
    # The VarDecl init value must still be present. If the real graph lacks it,
    # propagation-satisfaction must NOT paper over the missing value.
    my $spec = <<'END_IR';
%one  = Constant(1) :Int
%xn   = Constant("$x") :Str
%vx   = VarDecl(%xn, %one) :Int
%rx   = PadAccess(%vx, "$x") :Int
return %rx
control: %vx
END_IR
    # Real graph folds/propagates to the WRONG value (2, not 1).
    my $real = $C->build_graph_from_ir("%r = Constant(2) :Int\nreturn %r\n");
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'FAIL', 'the bound value Constant(1) is still required');
};

subtest 'the pad-explicit shape still matches a pad-explicit real graph (Chalk path)' => sub {
    # Propagation-satisfaction is additive: a producer that keeps the pad
    # (Chalk) still matches the pad-explicit spec directly.
    my $spec = <<'END_IR';
%one  = Constant(1) :Int
%xn   = Constant("$x") :Str
%vx   = VarDecl(%xn, %one) :Int
%rx   = PadAccess(%vx, "$x") :Int
return %rx
control: %vx
END_IR
    my $real = $C->build_graph_from_ir($spec);
    my $res  = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'PASS', 'pad-explicit spec still matches a pad-explicit real graph')
        or diag('missing: ' . join('; ', ($res->{missing} // [])->@*));
};

subtest 'a pad-KEEPING producer with a mis-typed pad still FAILs (repr not dropped)' => sub {
    # Propagation concedes EXISTENCE (B::SoN dropped the pad), not REPR. A
    # producer that KEEPS the pad (Chalk) but stamps it :Str where the spec
    # demands :Int is a real type bug the gate must still catch. (Review
    # finding: unconditional subsumption dropped the repr check.)
    my $spec = <<'END_IR';
%one  = Constant(1) :Int
%xn   = Constant("$x") :Str
%vx   = VarDecl(%xn, %one) :Int
%rx   = PadAccess(%vx, "$x") :Int
return %rx
control: %vx
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%one  = Constant(1) :Int
%xn   = Constant("$x") :Str
%vx   = VarDecl(%xn, %one) :Str
%rx   = PadAccess(%vx, "$x") :Str
return %rx
control: %vx
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'FAIL',
        'a kept-but-mis-typed pad is not papered over by propagation-satisfaction');
};

subtest 'operand-returning And/Or load unstamped but match the spec :Int (L1/L2)' => sub {
    # perl's && / || are operand-returning: `$a && $b` loads as And with no
    # repr (:-), but the corpus spec declares And :Int. The matcher accepts the
    # unstamped And/Or/DefinedOr against the spec's declared repr.
    my $spec = <<'END_IR';
%a   = Constant(3) :Int
%b   = Constant(7) :Int
%and = And(%a, %b) :Int
return %and
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%a   = Constant(3) :Int
%b   = Constant(7) :Int
%and = And(%a, %b)
return %and
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'PASS', 'unstamped And matches spec And :Int')
        or diag('missing: ' . join('; ', ($res->{missing} // [])->@*));
};

subtest 'a propagated scalar Assign is subsumed (A4/C1)' => sub {
    # perl propagates `my $x=1; $x=1; $x` to the final value, so no Assign
    # survives -- the real graph is just Constant(1). The corpus keeps the
    # assign-explicit shape; subsume the spec Assign when the real graph
    # propagated it away (has zero Assign).
    my $spec = <<'END_IR';
%xn  = Constant("$x") :Str
%vx  = VarDecl(%xn) :Int
%one = Constant(1) :Int
%lhs = PadAccess(%vx, "$x") :Int
%as  = Assign(%lhs, %one) :Int
%rx  = PadAccess(%vx, "$x") :Int
return %rx
control: %vx -> %as
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%one = Constant(1) :Int
return %one
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'PASS', 'propagated Assign subsumed')
        or diag('missing: ' . join('; ', ($res->{missing} // [])->@*));
};

subtest 'a propagated CompoundAssign is subsumed (K1/K2/C2)' => sub {
    my $spec = <<'END_IR';
%xn  = Constant("$i") :Str
%vx  = VarDecl(%xn) :Int
%one = Constant(1) :Int
%lhs = PadAccess(%vx, "$i") :Int
%ca  = CompoundAssign(%lhs, %one, op: "+=") :Int
%rx  = PadAccess(%vx, "$i") :Int
return %rx
control: %vx -> %ca
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%one = Constant(1) :Int
return %one
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'PASS', 'propagated CompoundAssign subsumed')
        or diag('missing: ' . join('; ', ($res->{missing} // [])->@*));
};

subtest 'an if/else with pure-value arms is subsumed by a real TernaryExpr (D1)' => sub {
    # perl propagates a branch whose arms are pure values into a select, so
    # B::SoN loads NumGt + TernaryExpr with NO If/Proj/Region. Subsume the
    # spec CFG scaffolding when the real graph has no If AND has the select.
    my $spec = <<'END_IR';
%n     = Constant(5) :Int
%zero  = Constant(0) :Int
%cmp   = NumGt(%n, %zero) :Bool
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%if    = If(%n, %cmp)
%proj0 = Proj(%if, index: 0)
%proj1 = Proj(%if, index: 1)
%region = Region(%proj0, %proj1)
%sel   = TernaryExpr(%cmp, %c1, %c2) :Int
return %sel
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%n    = Constant(5) :Int
%zero = Constant(0) :Int
%cmp  = NumGt(%n, %zero) :Bool
%c1   = Constant(1) :Int
%c2   = Constant(2) :Int
%sel  = TernaryExpr(%cmp, %c1, %c2) :Int
return %sel
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'PASS', 'if/else scaffolding subsumed by the real select')
        or diag('missing: ' . join('; ', ($res->{missing} // [])->@*));
};

subtest 'an element-store Assign is NOT subsumed (effectful, teeth)' => sub {
    # Only a pure scalar rebind (Assign with a PadAccess lhs) propagates. An
    # element store (Subscript lhs) is a real effect the real graph must carry;
    # subsuming it would mask a dropped array/hash write.
    my $spec = <<'END_IR';
%arr  = ArrayRef() :ArrayRef
%idx  = Constant(0) :Int
%lhs  = Subscript(%arr, %idx) :Int
%one  = Constant(1) :Int
%as   = Assign(%lhs, %one) :Int
%rd   = Subscript(%arr, %idx) :Int
return %rd
control: %arr -> %as
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%one = Constant(1) :Int
return %one
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'FAIL',
        'an element-store Assign stays required (not papered over)');
};

subtest 'a genuine If (no real select) is NOT subsumed (teeth)' => sub {
    # If the real graph has no TernaryExpr select, the spec If is a real branch
    # the producer failed to emit -- must FAIL, not be conceded. The If is on
    # the control chain (reachable from Return) and the value is a runtime
    # PadAccess (not a foldable ternary), so only the If rule is under test.
    my $spec = <<'END_IR';
%n     = Constant(5) :Int
%zero  = Constant(0) :Int
%cmp   = NumGt(%n, %zero) :Bool
%xn    = Constant("$x") :Str
%vx    = VarDecl(%xn) :Int
%if    = If(%vx, %cmp)
%proj0 = Proj(%if, index: 0)
%region = Region(%proj0)
%rx    = PadAccess(%vx, "$x") :Int
return %rx
control: %vx -> %if
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%n    = Constant(5) :Int
%zero = Constant(0) :Int
%cmp  = NumGt(%n, %zero) :Bool
%c1   = Constant(1) :Int
return %c1
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'FAIL',
        'a spec If with no real select stays required');
};

subtest 'a FieldAccess-store Assign is NOT subsumed (object-state effect, teeth)' => sub {
    # A field write-back ($self->{n} = ...) is an object-state mutation of
    # shared heap -- the RC4 class. Only a lexical PadAccess rebind propagates;
    # subsuming a FieldAccess store would false-green a dropped field write.
    # (Review finding: FieldAccess was wrongly treated as a pure rebind.)
    my $spec = <<'END_IR';
%fa_lv = FieldAccess(field_index: 0, field_stash: "C") :Int
%one   = Constant(1) :Int
%fa_rd = FieldAccess(field_index: 0, field_stash: "C") :Int
%add   = Add(%fa_rd, %one) :Int
%as    = Assign(%fa_lv, %add) :Int
%ret   = FieldAccess(field_index: 0, field_stash: "C") :Int
return %ret
control: %as
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%ret = FieldAccess(field_index: 0, field_stash: "C") :Int
return %ret
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'FAIL',
        'a dropped field write-back is not papered over');
};

subtest 'a dropped branch is NOT masked by one unrelated select (count gate, teeth)' => sub {
    # Two spec Ifs but the real graph has only ONE TernaryExpr: a genuinely
    # dropped branch. The count gate (real selects >= spec Ifs) refuses to
    # subsume -- one unrelated select must not satisfy two propagated branches.
    # The two Ifs are on the control chain (reachable from Return via
    # control_in), as in a real branch; the return value threads through them.
    my $spec = <<'END_IR';
%n     = Constant(5) :Int
%zero  = Constant(0) :Int
%cmp   = NumGt(%n, %zero) :Bool
%c1    = Constant(1) :Int
%if1   = If(%n, %cmp)
%if2   = If(%n, %cmp)
%sel   = TernaryExpr(%cmp, %c1, %c1) :Int
return %sel
control: %if1 -> %if2 -> %sel
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%n    = Constant(5) :Int
%zero = Constant(0) :Int
%cmp  = NumGt(%n, %zero) :Bool
%c1   = Constant(1) :Int
%sel  = TernaryExpr(%cmp, %c1, %c1) :Int
return %sel
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'FAIL',
        'two spec Ifs are not both satisfied by one real select');
};

subtest 'a ternary over a folded comparison collapses to its arm (statements Comparison)' => sub {
    # perl folds `1 < 2 ? 1 : 0` recursively: NumLt(1,2)->true, then the
    # ternary selects arm 1, so the real graph is just Constant(1). The corpus
    # keeps the NumLt+TernaryExpr shape; the fold subsumes the whole select.
    my $spec = <<'END_IR';
%one  = Constant(1) :Int
%two  = Constant(2) :Int
%cmp  = NumLt(%one, %two) :Bool
%t    = Constant(1) :Int
%f    = Constant(0) :Int
%tern = TernaryExpr(%cmp, %t, %f) :Int
return %tern
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%one = Constant(1) :Int
return %one
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'PASS', 'folded ternary subsumed to its selected arm')
        or diag('missing: ' . join('; ', ($res->{missing} // [])->@*));
};

subtest 'a Concat of string literals folds to the joined Constant (S3)' => sub {
    # perl folds `"hello" . " world"` to Constant("hello world"). The corpus
    # keeps the Concat shape; the fold subsumes it when the joined string is
    # present in the real graph.
    my $spec = <<'END_IR';
%lhs = Constant("hello") :Str
%rhs = Constant(" world") :Str
%cat = Concat(%lhs, %rhs) :Str
return %cat
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%s = Constant("hello world") :Str
return %s
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'PASS', 'folded Concat subsumed to the joined Constant')
        or diag('missing: ' . join('; ', ($res->{missing} // [])->@*));
};

subtest 'a Concat whose joined value is ABSENT still FAILs (teeth)' => sub {
    my $spec = <<'END_IR';
%lhs = Constant("hello") :Str
%rhs = Constant(" world") :Str
%cat = Concat(%lhs, %rhs) :Str
return %cat
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%s = Constant("goodbye") :Str
return %s
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'FAIL', 'a folded Concat whose value is absent stays required');
};

subtest 'a ternary whose folded arm is ABSENT from the real graph still FAILs (teeth)' => sub {
    # If perl would select arm 1 but the real graph carries a wrong value (2),
    # the fold's target Constant(1) is absent -> the ternary is NOT subsumed.
    my $spec = <<'END_IR';
%one  = Constant(1) :Int
%two  = Constant(2) :Int
%cmp  = NumLt(%one, %two) :Bool
%t    = Constant(1) :Int
%f    = Constant(0) :Int
%tern = TernaryExpr(%cmp, %t, %f) :Int
return %tern
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%wrong = Constant(2) :Int
return %wrong
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'FAIL',
        'a folded ternary whose arm value is absent stays required');
};

subtest 'an implicit deref subsumes the spec PostfixDeref (R4/R5)' => sub {
    # perl's aggregate deref ($r->[0]) is an implicit rv2av (an OpMap SKIP), so
    # B::SoN emits Subscript(ArrayRef, idx) directly -- no PostfixDeref. The
    # corpus keeps the explicit PostfixDeref shape; subsume it when the real
    # graph has none (the deref is implicit in the Subscript container).
    my $spec = <<'END_IR';
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%ref   = ArrayRef(%c1, %c2) :ArrayRef
%deref = PostfixDeref(%ref, sigil: "@") :Array
%idx   = Constant(0) :Int
%r     = Subscript(%deref, %idx) :Int
return %r
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%ref = ArrayRef(%c1, %c2) :ArrayRef
%idx = Constant(0) :Int
%r   = Subscript(%ref, %idx) :Int
return %r
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'PASS', 'implicit deref subsumes the spec PostfixDeref')
        or diag('missing: ' . join('; ', ($res->{missing} // [])->@*));
};

subtest 'a PostfixDeref is NOT subsumed when the real graph keeps one (teeth)' => sub {
    # A producer that DOES emit a PostfixDeref must match it (including the
    # wrapped aggregate); subsumption fires only when the real graph propagated
    # the deref away entirely.
    my $spec = <<'END_IR';
%c1    = Constant(1) :Int
%ref   = ArrayRef(%c1) :ArrayRef
%deref = PostfixDeref(%ref, sigil: "@") :Array
%idx   = Constant(0) :Int
%r     = Subscript(%deref, %idx) :Int
return %r
END_IR
    # real keeps a PostfixDeref but over a DIFFERENT (missing) aggregate shape
    my $real = $C->build_graph_from_ir(<<'END_IR');
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%ref   = ArrayRef(%c1, %c2) :ArrayRef
%deref = PostfixDeref(%ref, sigil: "@") :Array
%idx   = Constant(0) :Int
%r     = Subscript(%deref, %idx) :Int
return %r
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    # spec ArrayRef(1) vs real ArrayRef(1,2): the element Constant(2) is extra
    # in real (subset match is fine), but the spec's PostfixDeref IS present in
    # real, so it must match structurally -- this stays PASS (deref present both
    # sides). The teeth case that must FAIL is a KEPT deref with no match:
    is($res->{verdict}, 'PASS',
        'a real graph that keeps the PostfixDeref matches the spec deref');
};

subtest 'a Coerce(->Bool) feeding a Not is absorbed by the real Not (L4)' => sub {
    # perl's ! does its own truthiness coercion, so B::SoN emits Not(operand)
    # directly -- no explicit Coerce(Int->Bool). The corpus keeps the explicit
    # Coerce; subsume it when it feeds a Not and the real graph has none.
    my $spec = <<'END_IR';
%five = Constant(5) :Int
%b    = Coerce(%five : Int -> Bool) :Bool
%nb   = Not(%b) :Bool
return %nb
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%five = Constant(5) :Int
%nb   = Not(%five) :Bool
return %nb
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'PASS', 'the Not-feeding Coerce(->Bool) is absorbed')
        or diag('missing: ' . join('; ', ($res->{missing} // [])->@*));
};

subtest 'a Coerce NOT feeding a truthiness op stays required (teeth)' => sub {
    # A Coerce whose consumer is not a truthiness op (e.g. it feeds an Add) is
    # a real representation change the producer must carry; do not absorb it.
    my $spec = <<'END_IR';
%five = Constant(5) :Int
%n    = Coerce(%five : Int -> Num) :Num
%one  = Constant(1) :Num
%sum  = Add(%n, %one) :Num
return %sum
END_IR
    my $real = $C->build_graph_from_ir(<<'END_IR');
%five = Constant(5) :Int
%one  = Constant(1) :Num
%sum  = Add(%five, %one) :Num
return %sum
END_IR
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'FAIL',
        'a non-Bool Coerce feeding an Add stays required');
};

subtest 'a dead-store init is subsumed when a reassign overwrites it (C1)' => sub {
    # `my $x = 1; $x = 2; $x` — the init `1` is overwritten by `$x = 2` before
    # any read, so B::SoN const-propagates the pad to `2` and never materialises
    # the dead Constant(1). The corpus keeps the pre-optimisation shape; subsume
    # the init Constant of a propagated VarDecl that a reassigning Assign kills.
    my $spec = <<'END_IR';
%xn   = Constant("$x") :Str
%one  = Constant(1) :Int
%vx   = VarDecl(%xn, %one) :Int
%two  = Constant(2) :Int
%lhs  = PadAccess(%vx, "$x") :Int
%as   = Assign(%lhs, %two) :Int
%rx   = PadAccess(%vx, "$x") :Int
return %rx
control: %vx -> %as
END_IR
    my $real = $C->build_graph_from_ir("%r = Constant(2) :Int\nreturn %r\n");
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'PASS', 'dead Constant(1) subsumed; live Constant(2) matches')
        or diag('missing: ' . join('; ', ($res->{missing} // [])->@*));
};

subtest 'a live init (no reassign) is NOT subsumed (teeth)' => sub {
    # Without a reassigning Assign, the init value IS the result — it must stay
    # required so a producer that returns the wrong constant still FAILs. This
    # is what keeps the dead-store rule from swallowing every VarDecl init.
    my $spec = <<'END_IR';
%xn   = Constant("$x") :Str
%one  = Constant(1) :Int
%vx   = VarDecl(%xn, %one) :Int
%rx   = PadAccess(%vx, "$x") :Int
return %rx
control: %vx
END_IR
    my $real = $C->build_graph_from_ir("%r = Constant(2) :Int\nreturn %r\n");
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'FAIL',
        'no reassign -> the init Constant(1) is the live value and stays required');
};

subtest 'a reassign to the WRONG value still FAILs (dead-store value teeth)' => sub {
    # The dead init is subsumed, but the REASSIGNED value stays required: a
    # producer that propagates the wrong final value must still FAIL. Real graph
    # carries Constant(3), not the reassigned Constant(2).
    my $spec = <<'END_IR';
%xn   = Constant("$x") :Str
%one  = Constant(1) :Int
%vx   = VarDecl(%xn, %one) :Int
%two  = Constant(2) :Int
%lhs  = PadAccess(%vx, "$x") :Int
%as   = Assign(%lhs, %two) :Int
%rx   = PadAccess(%vx, "$x") :Int
return %rx
control: %vx -> %as
END_IR
    my $real = $C->build_graph_from_ir("%r = Constant(3) :Int\nreturn %r\n");
    my $res = $C->shape_subset_check($spec, $real);
    is($res->{verdict}, 'FAIL',
        'the reassigned value Constant(2) is still required (wrong value FAILs)');
};

done_testing();
