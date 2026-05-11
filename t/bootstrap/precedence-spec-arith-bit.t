# ABOUTME: Conformance test for Perl arithmetic and bitwise precedence per perlop.pod (5.42).
# ABOUTME: Covers L7-L9 (arithmetic/shift) and L14-L15 (bitwise) levels; TODO = current Chalk gap.
#
# This file is a TDD spec for the arithmetic-and-bitwise precedence cluster:
#
#     L7   left      * / % x
#     L8   left      + - .
#     L9   left      << >>
#     L14  left      & &.
#     L15  left      | |. ^ ^.
#
# (Verbatim from perlop.pod, "Operator Precedence and Associativity" section,
# Perl 5.42.0.)
#
# The L7-vs-L8 boundary (e.g. 2 + 3 * 4) and L8 left-associativity (e.g.
# 2 - 3 - 4) are already covered by t/bootstrap/precedence-spec.t — this file
# does not duplicate them. Subtests below address:
#
#   * L7 operator-set coverage (/, %, x) and L7 left-associativity
#   * L8 operator-set coverage (.) and L8 vs L7 mixed
#   * L9 (<<, >>) precedence and left-associativity vs L8/L7
#   * L14 (&, &.) precedence and left-associativity vs L9
#   * L15 (|, |., ^, ^.) precedence and left-associativity vs L14
#   * L15 vs L16 (&&) boundary (representative)
#   * Multi-level stacks across the cluster
#
# Each subtest cites the exact perlop level pair in its leading comment.

use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use PrecedenceSpecHelpers qw(parse_expr shape_of isa_with_shape);

use Chalk::IR::Node;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;
use Chalk::IR::Node::Modulo;
use Chalk::IR::Node::Repeat;
use Chalk::IR::Node::Concat;
use Chalk::IR::Node::LeftShift;
use Chalk::IR::Node::RightShift;
use Chalk::IR::Node::BitAnd;
use Chalk::IR::Node::BitOr;
use Chalk::IR::Node::BitXor;
use Chalk::IR::Node::And;

# ============================================================================
# L7 operator-set coverage (* / % x) and left-associativity
# ----------------------------------------------------------------------------
# perlop: "left   * / % x" — all four bind at the same level, left-associative.
# ============================================================================

subtest 'L7 / is left-associative: 12 / 6 / 2 is (12 / 6) / 2' => sub {
    # perlop: L7 left-assoc — 12 / 6 / 2 = Divide(Divide(12, 6), 2).
    my $expr = parse_expr('12 / 6 / 2');
    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::Divide',
        'top is Divide') or return;
    isa_with_shape($outer->inputs()->[1], 'Chalk::IR::Node::Divide',
        'left of outer Divide is another Divide (left-assoc)');
    is($outer->inputs()->[2]->value(), '2', 'right of outer Divide is 2');
};

subtest 'L7 % is at same level as *: 8 % 3 * 2 is (8 % 3) * 2' => sub {
    # perlop: L7 — % and * at same level, left-assoc, so left-to-right grouping.
    my $expr = parse_expr('8 % 3 * 2');
    my $mul = isa_with_shape($expr, 'Chalk::IR::Node::Multiply',
        'top is Multiply (left-assoc within L7)') or return;
    isa_with_shape($mul->inputs()->[1], 'Chalk::IR::Node::Modulo',
        'left of Multiply is Modulo (% bound first, left-to-right)');
    is($mul->inputs()->[2]->value(), '2', 'right of Multiply is 2');
};

subtest 'L7 x produces Repeat node: "a" x 3' => sub {
    # perlop: L7 — x is the repetition operator. Chalk emits Repeat (not
    # Multiply) — this subtest documents that distinction.
    my $expr = parse_expr('"a" x 3');
    my $rep = isa_with_shape($expr, 'Chalk::IR::Node::Repeat',
        'top is Repeat (x operator distinct from Multiply)') or return;
    is($rep->inputs()->[2]->value(), '3', 'count is 3');
};

subtest 'L7 x at same level as *: 2 * 3 x 4 is (2 * 3) x 4' => sub {
    # perlop: L7 — x and * at same level, left-assoc, so left-to-right grouping.
    my $expr = parse_expr('2 * 3 x 4');
    my $rep = isa_with_shape($expr, 'Chalk::IR::Node::Repeat',
        'top is Repeat (left-assoc within L7)') or return;
    isa_with_shape($rep->inputs()->[1], 'Chalk::IR::Node::Multiply',
        'left of Repeat is Multiply (* bound first, left-to-right)');
    is($rep->inputs()->[2]->value(), '4', 'right of Repeat is 4');
};

# ============================================================================
# L8 (+ - .) operator-set coverage
# ----------------------------------------------------------------------------
# perlop: "left   + - ." — concatenation . sits at the same level as + and -.
# ============================================================================

subtest 'L8 . is at same level as +: 1 . 2 + 3 is (1 . 2) + 3' => sub {
    # perlop: L8 — . and + at same level, left-assoc, so left-to-right grouping.
    my $expr = parse_expr('1 . 2 + 3');
    my $add = isa_with_shape($expr, 'Chalk::IR::Node::Add',
        'top is Add (left-assoc within L8)') or return;
    isa_with_shape($add->inputs()->[1], 'Chalk::IR::Node::Concat',
        'left of Add is Concat (. bound first, left-to-right)');
    is($add->inputs()->[2]->value(), '3', 'right of Add is 3');
};

subtest 'L8 . is at same level as +: 1 + 2 . 3 is (1 + 2) . 3' => sub {
    # perlop: L8 — same level, so left-to-right gives Concat outer.
    my $expr = parse_expr('1 + 2 . 3');
    my $concat = isa_with_shape($expr, 'Chalk::IR::Node::Concat',
        'top is Concat (left-assoc within L8)') or return;
    isa_with_shape($concat->inputs()->[1], 'Chalk::IR::Node::Add',
        'left of Concat is Add (+ bound first, left-to-right)');
    is($concat->inputs()->[2]->value(), '3', 'right of Concat is 3');
};

subtest 'L8 . is left-associative: 1 . 2 . 3 is (1 . 2) . 3' => sub {
    # perlop: L8 left-assoc — 1 . 2 . 3 = Concat(Concat(1, 2), 3).
    my $expr = parse_expr('"a" . "b" . "c"');
    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::Concat',
        'top is Concat') or return;
    isa_with_shape($outer->inputs()->[1], 'Chalk::IR::Node::Concat',
        'left of outer Concat is another Concat (left-assoc)');
};

# ============================================================================
# L8 vs L7: . tighter than nothing extra; . at L8 vs * at L7
# ----------------------------------------------------------------------------
# perlop: . at L8, * at L7 — * binds tighter than . (concat).
# ============================================================================

subtest 'L7 * tighter than L8 .: 1 . 2 * 3 is Concat(1, Multiply(2, 3))' => sub {
    # perlop: L7 (*) tighter than L8 (.) — multiplication groups first.
    my $expr = parse_expr('1 . 2 * 3');
    my $concat = isa_with_shape($expr, 'Chalk::IR::Node::Concat',
        'top is Concat') or return;
    is($concat->inputs()->[1]->value(), '1', 'left of Concat is 1');
    isa_with_shape($concat->inputs()->[2], 'Chalk::IR::Node::Multiply',
        'right of Concat is Multiply');
};

# ============================================================================
# L9 (<< >>) precedence vs L8 (+) and L7 (*)
# ----------------------------------------------------------------------------
# perlop: "left   << >>" — shift is below additive in the table, meaning
# additive binds tighter than shift.
# ============================================================================

subtest 'L8 + tighter than L9 <<: 2 + 3 << 4 is (2 + 3) << 4' => sub {
    # perlop: L8 (+) tighter than L9 (<<) — addition groups first.
    my $expr = parse_expr('2 + 3 << 4');
    my $shift = isa_with_shape($expr, 'Chalk::IR::Node::LeftShift',
        'top is LeftShift') or return;
    isa_with_shape($shift->inputs()->[1], 'Chalk::IR::Node::Add',
        'left of LeftShift is Add');
    is($shift->inputs()->[2]->value(), '4', 'right of LeftShift is 4');
};

subtest 'L8 + tighter than L9 <<: 1 << 2 + 3 is 1 << (2 + 3)' => sub {
    # perlop: L8 (+) tighter than L9 (<<) — addition on the right also groups
    # first, giving LeftShift(1, Add(2, 3)).
    my $expr = parse_expr('1 << 2 + 3');
    my $shift = isa_with_shape($expr, 'Chalk::IR::Node::LeftShift',
        'top is LeftShift') or return;
    is($shift->inputs()->[1]->value(), '1', 'left of LeftShift is 1');
    isa_with_shape($shift->inputs()->[2], 'Chalk::IR::Node::Add',
        'right of LeftShift is Add');
};

subtest 'L9 << is left-associative: 1 << 2 << 3 is (1 << 2) << 3' => sub {
    # perlop: L9 left-assoc — 1 << 2 << 3 = LeftShift(LeftShift(1, 2), 3).
    my $expr = parse_expr('1 << 2 << 3');
    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::LeftShift',
        'top is LeftShift') or return;
    isa_with_shape($outer->inputs()->[1], 'Chalk::IR::Node::LeftShift',
        'left of outer LeftShift is another LeftShift (left-assoc)');
    is($outer->inputs()->[2]->value(), '3', 'right of outer LeftShift is 3');
};

subtest 'L9 >> is left-associative: 16 >> 2 >> 1 is (16 >> 2) >> 1' => sub {
    # perlop: L9 left-assoc — 16 >> 2 >> 1 = RightShift(RightShift(16, 2), 1).
    my $expr = parse_expr('16 >> 2 >> 1');
    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::RightShift',
        'top is RightShift') or return;
    isa_with_shape($outer->inputs()->[1], 'Chalk::IR::Node::RightShift',
        'left of outer RightShift is another RightShift (left-assoc)');
    is($outer->inputs()->[2]->value(), '1', 'right of outer RightShift is 1');
};

subtest 'L9 << and >> at same level: 4 << 1 >> 2 is (4 << 1) >> 2' => sub {
    # perlop: L9 — << and >> at same level, left-assoc, so left-to-right.
    my $expr = parse_expr('4 << 1 >> 2');
    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::RightShift',
        'top is RightShift (left-assoc within L9)') or return;
    isa_with_shape($outer->inputs()->[1], 'Chalk::IR::Node::LeftShift',
        'left of RightShift is LeftShift (<< bound first, left-to-right)');
    is($outer->inputs()->[2]->value(), '2', 'right of RightShift is 2');
};

# ============================================================================
# L14 (& &.) precedence vs L9 (<<, >>) and left-associativity
# ----------------------------------------------------------------------------
# perlop: "left   & &." — bitwise AND below shifts, so shifts bind tighter.
# Note: &. (string-bitwise-AND) does not currently parse in Chalk.
# ============================================================================

subtest 'L9 << tighter than L14 &: 1 & 2 << 3 is 1 & (2 << 3)' => sub {
    # perlop: L9 (<<) tighter than L14 (&) — shift groups first.
    my $expr = parse_expr('1 & 2 << 3');
    my $and = isa_with_shape($expr, 'Chalk::IR::Node::BitAnd',
        'top is BitAnd') or return;
    is($and->inputs()->[1]->value(), '1', 'left of BitAnd is 1');
    isa_with_shape($and->inputs()->[2], 'Chalk::IR::Node::LeftShift',
        'right of BitAnd is LeftShift');
};

subtest 'L14 & is left-associative: 1 & 2 & 3 is (1 & 2) & 3' => sub {
    # perlop: L14 left-assoc — 1 & 2 & 3 = BitAnd(BitAnd(1, 2), 3).
    my $expr = parse_expr('1 & 2 & 3');
    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::BitAnd',
        'top is BitAnd') or return;
    isa_with_shape($outer->inputs()->[1], 'Chalk::IR::Node::BitAnd',
        'left of outer BitAnd is another BitAnd (left-assoc)');
    is($outer->inputs()->[2]->value(), '3', 'right of outer BitAnd is 3');
};

subtest 'L14 &. (string-bitwise-AND) parses: 1 &. 2' => sub {
    # perlop: L14 — &. is the string-bitwise-AND operator, same level as &.
    # Avoid isa_with_shape here — the helper lives in a different package and
    # Test::More's $TODO lookup doesn't reach across packages reliably.
    my $expr = parse_expr('1 &. 2');

    ok(defined $expr && ref($expr) && $expr->isa('Chalk::IR::Node::BitAnd'),
        'top is BitAnd-equivalent for &.')
        or diag("  got shape: " . shape_of($expr));
};

# ============================================================================
# L15 (| |. ^ ^.) precedence vs L14 (&) and left-associativity
# ----------------------------------------------------------------------------
# perlop: "left   | |. ^ ^." — bitwise OR/XOR below bitwise AND, so & binds
# tighter than | and ^.
# ============================================================================

subtest 'L14 & tighter than L15 |: 1 | 2 & 3 is 1 | (2 & 3)' => sub {
    # perlop: L14 (&) tighter than L15 (|) — AND groups first.
    my $expr = parse_expr('1 | 2 & 3');
    my $or = isa_with_shape($expr, 'Chalk::IR::Node::BitOr',
        'top is BitOr') or return;
    is($or->inputs()->[1]->value(), '1', 'left of BitOr is 1');
    isa_with_shape($or->inputs()->[2], 'Chalk::IR::Node::BitAnd',
        'right of BitOr is BitAnd');
};

subtest 'L14 & tighter than L15 |: 1 & 2 | 3 is (1 & 2) | 3' => sub {
    # perlop: L14 (&) tighter than L15 (|) — AND on the left also groups first.
    my $expr = parse_expr('1 & 2 | 3');
    my $or = isa_with_shape($expr, 'Chalk::IR::Node::BitOr',
        'top is BitOr') or return;
    isa_with_shape($or->inputs()->[1], 'Chalk::IR::Node::BitAnd',
        'left of BitOr is BitAnd');
    is($or->inputs()->[2]->value(), '3', 'right of BitOr is 3');
};

subtest 'L15 | is left-associative: 1 | 2 | 3 is (1 | 2) | 3' => sub {
    # perlop: L15 left-assoc — 1 | 2 | 3 = BitOr(BitOr(1, 2), 3).
    my $expr = parse_expr('1 | 2 | 3');
    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::BitOr',
        'top is BitOr') or return;
    isa_with_shape($outer->inputs()->[1], 'Chalk::IR::Node::BitOr',
        'left of outer BitOr is another BitOr (left-assoc)');
    is($outer->inputs()->[2]->value(), '3', 'right of outer BitOr is 3');
};

subtest 'L15 ^ is left-associative: 1 ^ 2 ^ 3 is (1 ^ 2) ^ 3' => sub {
    # perlop: L15 left-assoc — 1 ^ 2 ^ 3 = BitXor(BitXor(1, 2), 3).
    my $expr = parse_expr('1 ^ 2 ^ 3');
    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::BitXor',
        'top is BitXor') or return;
    isa_with_shape($outer->inputs()->[1], 'Chalk::IR::Node::BitXor',
        'left of outer BitXor is another BitXor (left-assoc)');
    is($outer->inputs()->[2]->value(), '3', 'right of outer BitXor is 3');
};

subtest 'L15 | and ^ at same level: 1 ^ 2 | 3 is (1 ^ 2) | 3' => sub {
    # perlop: L15 — ^ and | at same level, left-assoc, so left-to-right.
    my $expr = parse_expr('1 ^ 2 | 3');
    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::BitOr',
        'top is BitOr (left-assoc within L15)') or return;
    isa_with_shape($outer->inputs()->[1], 'Chalk::IR::Node::BitXor',
        'left of BitOr is BitXor (^ bound first, left-to-right)');
    is($outer->inputs()->[2]->value(), '3', 'right of BitOr is 3');
};

# ============================================================================
# L15 vs L16 boundary (representative)
# ----------------------------------------------------------------------------
# perlop: | at L15, && at L16 — L15 binds tighter than L16, so bitwise-OR
# groups before logical-AND.
# ============================================================================

subtest 'L15 | tighter than L16 &&: 1 | 2 && 3 is (1 | 2) && 3' => sub {
    # perlop: L15 (|) tighter than L16 (&&) — bitwise-OR groups first.
    my $expr = parse_expr('1 | 2 && 3');
    my $and = isa_with_shape($expr, 'Chalk::IR::Node::And',
        'top is And') or return;
    isa_with_shape($and->inputs()->[1], 'Chalk::IR::Node::BitOr',
        'left of And is BitOr');
    is($and->inputs()->[2]->value(), '3', 'right of And is 3');
};

# ============================================================================
# Multi-level stacks across the cluster
# ----------------------------------------------------------------------------
# These exercise three or more cluster levels at once to confirm the
# precedence chain is consistent end-to-end.
# ============================================================================

subtest 'L8/L9/L15 stack: 1 << 2 | 3 & 4 is (1 << 2) | (3 & 4)' => sub {
    # perlop: L9 (<<) tighter than L14 (&) tighter than L15 (|). Both shift and
    # AND group below the OR; left side is a shift, right side is an AND.
    my $expr = parse_expr('1 << 2 | 3 & 4');
    my $or = isa_with_shape($expr, 'Chalk::IR::Node::BitOr',
        'top is BitOr') or return;
    isa_with_shape($or->inputs()->[1], 'Chalk::IR::Node::LeftShift',
        'left of BitOr is LeftShift');
    isa_with_shape($or->inputs()->[2], 'Chalk::IR::Node::BitAnd',
        'right of BitOr is BitAnd');
};

subtest 'L8/L9 stack: 1 . 2 + 3 << 4 is ((1 . 2) + 3) << 4' => sub {
    # perlop: L8 (. and +) tighter than L9 (<<); within L8, left-to-right
    # gives Concat first, then Add. Top is LeftShift over the Add.
    my $expr = parse_expr('1 . 2 + 3 << 4');
    my $shift = isa_with_shape($expr, 'Chalk::IR::Node::LeftShift',
        'top is LeftShift') or return;
    my $add = isa_with_shape($shift->inputs()->[1], 'Chalk::IR::Node::Add',
        'left of LeftShift is Add') or return;
    isa_with_shape($add->inputs()->[1], 'Chalk::IR::Node::Concat',
        'left of Add is Concat');
    is($shift->inputs()->[2]->value(), '4', 'right of LeftShift is 4');
};

done_testing;
