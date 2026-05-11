# ABOUTME: Conformance test for perlop.pod L11/L12/L13/L16/L17 (logical + comparison) precedence.
# ABOUTME: Each subtest cites the perlop level pair and asserts IR shape; TODO marks current gaps.
#
# This file is a TDD spec: every subtest is derived verbatim from perlop.pod's
# documented precedence table for Perl 5.42, not from Chalk's
# PrecedenceTable.pm. Tests that fail on current Chalk are marked TODO; the
# TODO inventory is the Precedence-semiring work backlog for the
# logical/comparison cluster.
#
# Cluster (perlop.pod, "Operator Precedence and Associativity"):
#
#     L11  nonassoc    isa
#     L12  chained     < > <= >= lt gt le ge
#     L13  chain/na    == != eq ne <=> cmp ~~
#     L14  left        & &.                       (boundary above)
#     L16  left        &&
#     L17  left        || ^^ //
#     L18  nonassoc    .. ...                     (boundary below)
#
# Lower L-number = tighter binding. L16 vs L17 (`$a || $b && $c`) is covered by
# the sibling file precedence-spec.t and intentionally NOT duplicated here.

use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use PrecedenceSpecHelpers qw(parse_expr shape_of isa_with_shape);

use Chalk::IR::Node;
use Chalk::IR::Node::And;
use Chalk::IR::Node::Or;
use Chalk::IR::Node::DefinedOr;
use Chalk::IR::Node::Xor;
use Chalk::IR::Node::Not;
use Chalk::IR::Node::IsaOp;
use Chalk::IR::Node::NumLt;
use Chalk::IR::Node::NumGt;
use Chalk::IR::Node::NumLe;
use Chalk::IR::Node::NumGe;
use Chalk::IR::Node::NumEq;
use Chalk::IR::Node::NumNe;
use Chalk::IR::Node::NumCmp;
use Chalk::IR::Node::StrLt;
use Chalk::IR::Node::StrGt;
use Chalk::IR::Node::StrLe;
use Chalk::IR::Node::StrGe;
use Chalk::IR::Node::StrEq;
use Chalk::IR::Node::StrNe;
use Chalk::IR::Node::StrCmp;
use Chalk::IR::Node::BitAnd;
use Chalk::IR::Node::BitOr;
use Chalk::IR::Node::Range;

# ============================================================================
# L11 (isa) baselines
# ----------------------------------------------------------------------------
# perlop "Class Instance Operator":
#   "Binary isa evaluates to true when the left argument is an object
#    instance of the class (or a subclass derived from that class) given by
#    the right argument. ... The right argument may give the class either
#    as a bareword or a scalar expression that yields a string class name."
# ============================================================================

subtest 'L11 isa with bareword RHS: $obj isa Some::Class' => sub {
    # perlop: nonassoc isa  (single application — nothing to chain)
    my $expr = parse_expr('$obj isa Foo');
    my $isa = isa_with_shape($expr, 'Chalk::IR::Node::IsaOp',
        'top is IsaOp') or return;
    is($isa->inputs()->[1]->value(), '$obj', 'left of isa is $obj');
    is($isa->inputs()->[2]->value(), 'Foo',  'right of isa is bareword Foo');
};

subtest 'L11 isa with string RHS: $obj isa "Foo"' => sub {
    # perlop: 'isa "Different::Class"' — string literal is allowed RHS.
    my $expr = parse_expr('$obj isa "Foo"');
    my $isa = isa_with_shape($expr, 'Chalk::IR::Node::IsaOp',
        'top is IsaOp') or return;
    is($isa->inputs()->[1]->value(), '$obj', 'left of isa is $obj');
};

subtest 'L11 isa with scalar RHS: $obj isa $cls' => sub {
    # perlop: 'isa $name_of_class' — scalar yielding class name is allowed RHS.
    my $expr = parse_expr('$obj isa $cls');
    my $isa = isa_with_shape($expr, 'Chalk::IR::Node::IsaOp',
        'top is IsaOp') or return;
    is($isa->inputs()->[1]->value(), '$obj', 'left of isa is $obj');
    is($isa->inputs()->[2]->value(), '$cls', 'right of isa is scalar $cls');
};

# ============================================================================
# L11 (isa) non-associativity
# ----------------------------------------------------------------------------
# perlop table: "nonassoc    isa". Per the section "Some operators are instead
# non-associative, meaning that it is a syntax error to use a sequence of
# those operators of the same precedence."  So `$a isa Foo isa Bar` MUST be a
# parse error.
# ============================================================================

subtest 'L11 isa is non-associative: $a isa Foo isa Bar must error' => sub {
    # perlop: "nonassoc isa" + "syntax error to use a sequence of those
    # operators of the same precedence."
    my $expr = parse_expr('$a isa Foo isa Bar');

    TODO: {
        local $TODO = 'L11 nonassoc not enforced; Chalk parses left-assoc';
        ok(!defined $expr,
            'chained isa should be a parse error (perlop nonassoc)')
            or diag("  got shape: " . shape_of($expr));
    }
};

# ============================================================================
# L11 (isa) vs L13 (==): isa tighter
# ----------------------------------------------------------------------------
# perlop table: isa at L11, == at L13. Lower L = tighter, so
# `$obj isa Foo == $b` is `($obj isa Foo) == $b` = NumEq(IsaOp(...), $b).
# ============================================================================

subtest 'L11 isa tighter than L13 ==: $obj isa Foo == $b' => sub {
    my $expr = parse_expr('$obj isa Foo == $b');
    my $eq = isa_with_shape($expr, 'Chalk::IR::Node::NumEq',
        'top is NumEq') or return;
    isa_with_shape($eq->inputs()->[1], 'Chalk::IR::Node::IsaOp',
        'left of NumEq is IsaOp');
    is($eq->inputs()->[2]->value(), '$b', 'right of NumEq is $b');
};

# ============================================================================
# L11 isa vs L17 ||: isa much tighter
# ----------------------------------------------------------------------------
# perlop table: isa at L11, || at L17. `$obj isa Foo || $b` is
# `($obj isa Foo) || $b` = Or(IsaOp(...), $b).
# ============================================================================

subtest 'L11 isa tighter than L17 ||: $obj isa Foo || $b' => sub {
    my $expr = parse_expr('$obj isa Foo || $b');
    my $or = isa_with_shape($expr, 'Chalk::IR::Node::Or',
        'top is Or') or return;
    isa_with_shape($or->inputs()->[1], 'Chalk::IR::Node::IsaOp',
        'left of Or is IsaOp');
    is($or->inputs()->[2]->value(), '$b', 'right of Or is $b');
};

# ============================================================================
# L12 (< > <= >= lt gt le ge) baselines and chaining semantics
# ----------------------------------------------------------------------------
# perlop "Operator Precedence and Associativity":
#   "Some comparison operators, as their associativity, chain with some
#    operators of the same precedence (but never with operators of different
#    precedence). This chaining means that each comparison is performed on
#    the two arguments surrounding it, with each interior argument taking
#    part in two comparisons, and the comparison results are implicitly
#    ANDed. Thus '$x < $y <= $z' behaves exactly like '$x < $y && $y <= $z',
#    assuming that '$y' is as simple a scalar as it looks."
# ============================================================================

subtest 'L12 < baseline: $a < $b is NumLt($a, $b)' => sub {
    my $expr = parse_expr('$a < $b');
    my $lt = isa_with_shape($expr, 'Chalk::IR::Node::NumLt',
        'top is NumLt') or return;
    is($lt->inputs()->[1]->value(), '$a', 'left is $a');
    is($lt->inputs()->[2]->value(), '$b', 'right is $b');
};

subtest 'L12 lt baseline: $a lt $b is StrLt($a, $b)' => sub {
    my $expr = parse_expr('$a lt $b');
    my $lt = isa_with_shape($expr, 'Chalk::IR::Node::StrLt',
        'top is StrLt') or return;
    is($lt->inputs()->[1]->value(), '$a', 'left is $a');
    is($lt->inputs()->[2]->value(), '$b', 'right is $b');
};

subtest 'L12 chained: $x < $y < $z behaves like $x < $y && $y < $z' => sub {
    # perlop: "'$x < $y <= $z' behaves exactly like '$x < $y && $y <= $z'"
    # — chaining rewrites a sequence of L12 ops into an &&-of-pairs.
    my $expr = parse_expr('$x < $y < $z');

    TODO: {
        local $TODO = 'L12 chained-comparison rewrite not implemented; Chalk parses left-assoc';
        ok(ref($expr) && $expr->isa('Chalk::IR::Node::And'),
            'top is And (chained-comparison rewrite)')
            or diag("  got shape: " . shape_of($expr));
    }
};

subtest 'L12 chained mixed: $a < $b <= $c behaves like $a < $b && $b <= $c' => sub {
    # perlop's example uses exactly this mix: '$x < $y <= $z'.
    my $expr = parse_expr('$a < $b <= $c');

    TODO: {
        local $TODO = 'L12 chained-comparison rewrite not implemented; Chalk parses left-assoc';
        ok(ref($expr) && $expr->isa('Chalk::IR::Node::And'),
            'top is And (chained-comparison rewrite)')
            or diag("  got shape: " . shape_of($expr));
    }
};

subtest 'L12 chained string: $a lt $b lt $c behaves like $a lt $b && $b lt $c' => sub {
    # perlop says lt/gt/le/ge are at L12 and chain identically.
    my $expr = parse_expr('$a lt $b lt $c');

    TODO: {
        local $TODO = 'L12 chained-comparison rewrite not implemented; Chalk parses left-assoc';
        ok(ref($expr) && $expr->isa('Chalk::IR::Node::And'),
            'top is And (chained-comparison rewrite)')
            or diag("  got shape: " . shape_of($expr));
    }
};

# ============================================================================
# L12 vs L13 boundary: < tighter than ==
# ----------------------------------------------------------------------------
# perlop "Relational Operators": "Beware that they do not chain with equality
# operators, which have lower precedence."  So `$a < $b == $c` is
# `($a < $b) == $c` = NumEq(NumLt($a,$b), $c).
# ============================================================================

subtest 'L12 < tighter than L13 ==: $a < $b == $c is NumEq(NumLt, $c)' => sub {
    my $expr = parse_expr('$a < $b == $c');
    my $eq = isa_with_shape($expr, 'Chalk::IR::Node::NumEq',
        'top is NumEq') or return;
    isa_with_shape($eq->inputs()->[1], 'Chalk::IR::Node::NumLt',
        'left of NumEq is NumLt');
    is($eq->inputs()->[2]->value(), '$c', 'right of NumEq is $c');
};

# ============================================================================
# L13 (== != eq ne <=> cmp ~~) non-associativity and chaining boundary
# ----------------------------------------------------------------------------
# perlop table: "chain/na    == != eq ne <=> cmp ~~".  Per perlop:
#   "Some operators are instead non-associative, meaning that it is a syntax
#    error to use a sequence of those operators of the same precedence."
# AND from "Equality Operators": these L13 ops do NOT chain with each other
# the way L12 ops do — they are non-associative when stacked with themselves.
# ============================================================================

subtest 'L13 == baseline: $a == $b is NumEq($a, $b)' => sub {
    my $expr = parse_expr('$a == $b');
    my $eq = isa_with_shape($expr, 'Chalk::IR::Node::NumEq',
        'top is NumEq') or return;
    is($eq->inputs()->[1]->value(), '$a', 'left is $a');
    is($eq->inputs()->[2]->value(), '$b', 'right is $b');
};

subtest 'L13 cmp baseline: $a cmp $b is StrCmp($a, $b)' => sub {
    my $expr = parse_expr('$a cmp $b');
    my $cmp = isa_with_shape($expr, 'Chalk::IR::Node::StrCmp',
        'top is StrCmp') or return;
    is($cmp->inputs()->[1]->value(), '$a', 'left is $a');
    is($cmp->inputs()->[2]->value(), '$b', 'right is $b');
};

subtest 'L13 <=> baseline: $a <=> $b is NumCmp($a, $b)' => sub {
    my $expr = parse_expr('$a <=> $b');
    my $cmp = isa_with_shape($expr, 'Chalk::IR::Node::NumCmp',
        'top is NumCmp') or return;
    is($cmp->inputs()->[1]->value(), '$a', 'left is $a');
    is($cmp->inputs()->[2]->value(), '$b', 'right is $b');
};

subtest 'L13 == is non-associative: $a == $b == $c must error' => sub {
    # perlop: "chain/na" — equality ops do NOT chain (per "Equality Operators"
    # which only refers back to the chained-comparison section for L12), and
    # the "/na" half of "chain/na" makes them non-associative when stacked
    # with themselves at the same level.  perlop's general non-associativity
    # rule: "syntax error to use a sequence of those operators of the same
    # precedence."
    my $expr = parse_expr('$a == $b == $c');

    TODO: {
        local $TODO = 'L13 nonassoc not enforced; Chalk parses left-assoc silently';
        ok(!defined $expr,
            'chained == should be a parse error (perlop chain/na)')
            or diag("  got shape: " . shape_of($expr));
    }
};

# ============================================================================
# L13 (~~) — smartmatch
# ----------------------------------------------------------------------------
# perlop "Smartmatch Operator": present in the L13 table row "== != eq ne
# <=> cmp ~~". Smartmatch was deprecated and is largely removed from modern
# Perl; Chalk's grammar does not admit it. Encode that as a parse-failure
# expectation so the assertion is explicit.
# ============================================================================

subtest 'L13 ~~ smartmatch: parse-failure (Chalk grammar does not admit ~~)' => sub {
    # perlop lists ~~ at L13 but it has been removed from the modern Perl
    # subset Chalk targets. Confirm parser rejects rather than mis-parses.
    my $expr = parse_expr('$a ~~ $b');
    ok(!defined $expr,
        '~~ smartmatch is rejected by Chalk grammar')
        or diag("  got shape: " . shape_of($expr));
};

# ============================================================================
# L13 vs L14 boundary: == tighter than &
# ----------------------------------------------------------------------------
# perlop table: == at L13, & at L14. Lower L = tighter, so `$a & $b == $c` is
# `$a & ($b == $c)` = BitAnd($a, NumEq($b,$c)).
# ============================================================================

subtest 'L13 == tighter than L14 &: $a & $b == $c is BitAnd($a, NumEq)' => sub {
    my $expr = parse_expr('$a & $b == $c');
    my $bitand = isa_with_shape($expr, 'Chalk::IR::Node::BitAnd',
        'top is BitAnd') or return;
    is($bitand->inputs()->[1]->value(), '$a', 'left of BitAnd is $a');
    isa_with_shape($bitand->inputs()->[2], 'Chalk::IR::Node::NumEq',
        'right of BitAnd is NumEq');
};

# ============================================================================
# L13 vs L16 boundary: == tighter than &&
# ----------------------------------------------------------------------------
# perlop table: == at L13, && at L16. `$a == $b && $c == $d` is
# `($a == $b) && ($c == $d)` = And(NumEq, NumEq).
# ============================================================================

subtest 'L13 == tighter than L16 &&: $a == $b && $c == $d' => sub {
    my $expr = parse_expr('$a == $b && $c == $d');
    my $and = isa_with_shape($expr, 'Chalk::IR::Node::And',
        'top is And') or return;
    isa_with_shape($and->inputs()->[1], 'Chalk::IR::Node::NumEq',
        'left of And is NumEq');
    isa_with_shape($and->inputs()->[2], 'Chalk::IR::Node::NumEq',
        'right of And is NumEq');
};

# ============================================================================
# L12 vs L17 boundary: < tighter than ||
# ----------------------------------------------------------------------------
# perlop table: < at L12, || at L17. `$x < 0 || $y > 10` is
# `($x < 0) || ($y > 10)` = Or(NumLt, NumGt).
# ============================================================================

subtest 'L12 < tighter than L17 ||: $x < 0 || $y > 10' => sub {
    my $expr = parse_expr('$x < 0 || $y > 10');
    my $or = isa_with_shape($expr, 'Chalk::IR::Node::Or',
        'top is Or') or return;
    isa_with_shape($or->inputs()->[1], 'Chalk::IR::Node::NumLt',
        'left of Or is NumLt');
    isa_with_shape($or->inputs()->[2], 'Chalk::IR::Node::NumGt',
        'right of Or is NumGt');
};

# ============================================================================
# L17 (|| ^^ //) — defined-or vs logical-or
# ----------------------------------------------------------------------------
# perlop "C-style Logical Or, Xor, and Defined Or":
#   "Perl's // operator is related to its C-style 'or'. In fact, it's
#    exactly the same as ||, except that it tests the left hand side's
#    definedness instead of its truth."
# So `0 // $x` and `0 || $x` MUST produce different node types (DefinedOr vs
# Or). This is the load-bearing distinction for defaulting idioms.
# ============================================================================

subtest 'L17 // is DefinedOr (distinct from ||): 0 // $x' => sub {
    # perlop: '// tests the left hand side's definedness instead of its
    # truth' — so 0 // $x returns 0 (defined), but 0 || $x returns $x.
    # IR must distinguish these.
    my $expr = parse_expr('0 // $x');
    my $node = isa_with_shape($expr, 'Chalk::IR::Node::DefinedOr',
        'top is DefinedOr (NOT Or)') or return;
    is($node->inputs()->[1]->value(), '0',  'left of DefinedOr is 0');
    is($node->inputs()->[2]->value(), '$x', 'right of DefinedOr is $x');
};

subtest 'L17 || is Or (distinct from //): 0 || $x' => sub {
    my $expr = parse_expr('0 || $x');
    my $node = isa_with_shape($expr, 'Chalk::IR::Node::Or',
        'top is Or (NOT DefinedOr)') or return;
    is($node->inputs()->[1]->value(), '0',  'left of Or is 0');
    is($node->inputs()->[2]->value(), '$x', 'right of Or is $x');
};

# ============================================================================
# L17 (^^) — logical xor
# ----------------------------------------------------------------------------
# perlop: "Binary ^^ performs a logical XOR operation. Both operands are
# evaluated and the result is true only if exactly one of the operands is
# true." Added in Perl 5.40. Chalk's grammar may not admit it; encode the
# observed behavior as a TODO so the gap is explicit.
# ============================================================================

subtest 'L17 ^^ logical-xor: $a ^^ $b' => sub {
    # perlop lists ^^ alongside || and // at L17. ^^ (Perl 5.40+ logical-xor)
    # maps to Chalk::IR::Node::Xor, paralleling &&-as-And and ||-as-Or.
    my $expr = parse_expr('$a ^^ $b');

    ok(ref($expr) && $expr->isa('Chalk::IR::Node::Xor'),
        'top is Xor (^^ admitted by grammar)')
        or diag("  got shape: " . shape_of($expr));
};

# ============================================================================
# L17 vs L18 boundary: || tighter than ..
# ----------------------------------------------------------------------------
# perlop table: || at L17, .. at L18. `$a || $b .. $c` is
# `($a || $b) .. $c` = Range(Or($a,$b), $c).
# ============================================================================

subtest 'L17 || tighter than L18 ..: $a || $b .. $c is Range(Or, $c)' => sub {
    my $expr = parse_expr('$a || $b .. $c');
    my $range = isa_with_shape($expr, 'Chalk::IR::Node::Range',
        'top is Range') or return;
    isa_with_shape($range->inputs()->[1], 'Chalk::IR::Node::Or',
        'left of Range is Or');
    is($range->inputs()->[2]->value(), '$c', 'right of Range is $c');
};

# ============================================================================
# Mixed three-level stacking: L13 + L16 + L17
# ----------------------------------------------------------------------------
# perlop table: == at L13 (tightest), && at L16, || at L17 (loosest).
# `$a == $b && $c == $d || $e` groups as
# `(($a == $b) && ($c == $d)) || $e` = Or(And(NumEq, NumEq), $e).
# ============================================================================

subtest 'L13 + L16 + L17 stack: $a == $b && $c == $d || $e' => sub {
    my $expr = parse_expr('$a == $b && $c == $d || $e');
    my $or = isa_with_shape($expr, 'Chalk::IR::Node::Or',
        'top is Or') or return;
    my $and = isa_with_shape($or->inputs()->[1], 'Chalk::IR::Node::And',
        'left of Or is And') or return;
    isa_with_shape($and->inputs()->[1], 'Chalk::IR::Node::NumEq',
        'left of And is NumEq');
    isa_with_shape($and->inputs()->[2], 'Chalk::IR::Node::NumEq',
        'right of And is NumEq');
    is($or->inputs()->[2]->value(), '$e', 'right of Or is $e');
};

# ============================================================================
# Same-level associativity within L17: || and // are both left-associative
# ----------------------------------------------------------------------------
# perlop table: "left   || ^^ //". They share L17 and group left-to-right.
# `$a || $b // $c` therefore parses as `($a || $b) // $c` =
# DefinedOr(Or($a,$b), $c).
# ============================================================================

subtest 'L17 || and // share level (left-assoc): $a || $b // $c' => sub {
    my $expr = parse_expr('$a || $b // $c');
    my $defor = isa_with_shape($expr, 'Chalk::IR::Node::DefinedOr',
        'top is DefinedOr (left-assoc same-level)') or return;
    isa_with_shape($defor->inputs()->[1], 'Chalk::IR::Node::Or',
        'left of DefinedOr is Or');
    is($defor->inputs()->[2]->value(), '$c', 'right of DefinedOr is $c');
};

done_testing;
