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

done_testing();
