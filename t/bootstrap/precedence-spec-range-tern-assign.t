# ABOUTME: Conformance test for Perl operator precedence per perlop.pod (Perl 5.42).
# ABOUTME: Covers L18 (range), L19 (ternary ?:), L20 (= and compound assign + control-flow).
#
# This file is a TDD spec: every subtest is derived from perlop.pod's
# documented precedence table, not from Chalk's PrecedenceTable.pm. Tests that
# fail on current Chalk are marked TODO; the TODO inventory is the
# Precedence-semiring work backlog for the range/ternary/assignment cluster.
#
# perlop.pod's precedence table (Perl 5.42, highest to lowest), with this
# file's cluster boxed:
#
#     ...
#     L17  left      || ^^ //
#   ┌─L18  nonassoc  .. ...
#   │ L19  right     ?:
#   └─L20  right     = += -= *= etc., goto, last, next, redo, dump
#     L21  left      , =>
#     ...
#
# Lower number = tighter binding. Tests below cite this table by L-number.
#
# perlop.pod section quotes (verbatim):
#   - L1108 "Range Operators" — "..." and ".." behave as range/flip-flop;
#     "The precedence is a little lower than || and &&." That places .. at
#     L18, below L17 (||), so $a || $b .. $c parses as ($a || $b) .. $c.
#   - L1322 "Conditional Operator" — ternary "?:", right-associative.
#     The pod's worked example: "$x % 2 ? $x += 10 : $x += 2" really means
#     "(($x % 2) ? ($x += 10) : $x) += 2" — i.e., ternary binds tighter than
#     compound assignment, but assignment binds tighter than the *outer* ?
#     because of right-associative ?: with assignment-rhs-eats-everything-
#     under-?:.
#   - L1362 "Assignment Operators" — "=" and the family **= += -= *= /= %=
#     x= .= <<= >>= &= |= ^= &.= |.= ^.= &&= ||= //= ^^= "all have the
#     precedence of assignment" and the family is right-associative.

use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use PrecedenceSpecHelpers qw(parse_expr shape_of isa_with_shape);

use Chalk::IR::Node;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::And;
use Chalk::IR::Node::Assign;
use Chalk::IR::Node::CompoundAssign;
use Chalk::IR::Node::TernaryExpr;
use Chalk::IR::Node::Range;
use Chalk::IR::Node::Or;
use Chalk::IR::Node::Constant;

# ============================================================================
# L20 (=) right-associativity
# ----------------------------------------------------------------------------
# perlop L1362: assignment family is right-associative.
# $a = $b = $c parses as $a = ($b = $c) = Assign($a, Assign($b, $c)).
# Note: Chalk's binary-op nodes carry the operator string as inputs[0], with
# operands at inputs[1] and inputs[2]; BinOp also exposes left()/right().
# ============================================================================

subtest 'L20 = is right-associative: $a = $b = $c is Assign($a, Assign($b, $c))' => sub {
    my $expr = parse_expr('$a = $b = $c');
    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::Assign',
        'top is Assign') or return;
    is($outer->left()->value(), '$a', 'outer left is $a');
    my $inner = isa_with_shape($outer->right(), 'Chalk::IR::Node::Assign',
        'outer right is another Assign (right-assoc)') or return;
    is($inner->left()->value(), '$b', 'inner left is $b');
    is($inner->right()->value(), '$c', 'inner right is $c');
};

# ============================================================================
# L20 compound (+=) right-associativity, mixed with another compound
# ----------------------------------------------------------------------------
# perlop: all assignment-family operators share L20 right-assoc, so
# $a += $b *= $c parses as $a += ($b *= $c) = CompoundAssign(+=, $a,
# CompoundAssign(*=, $b, $c)).
# ============================================================================

subtest 'L20 += and *= right-associate together: $a += $b *= $c' => sub {
    my $expr = parse_expr('$a += $b *= $c');
    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::CompoundAssign',
        'top is CompoundAssign') or return;
    is($outer->inputs()->[0]->value(), '+=', 'outer op is +=');
    is($outer->inputs()->[1]->value(), '$a', 'outer left is $a');
    my $inner = isa_with_shape($outer->inputs()->[2], 'Chalk::IR::Node::CompoundAssign',
        'outer right is another CompoundAssign (right-assoc)') or return;
    is($inner->inputs()->[0]->value(), '*=', 'inner op is *=');
    is($inner->inputs()->[1]->value(), '$b', 'inner left is $b');
    is($inner->inputs()->[2]->value(), '$c', 'inner right is $c');
};

# ============================================================================
# L20 //= compound assignment: also right-assoc, also at L20
# ----------------------------------------------------------------------------
# perlop L1362: //= is in the assignment-family list. Just verify it parses
# and produces CompoundAssign with op='//='.
# ============================================================================

subtest 'L20 //= produces CompoundAssign with op "//="' => sub {
    my $expr = parse_expr('$a //= $b');
    my $ca = isa_with_shape($expr, 'Chalk::IR::Node::CompoundAssign',
        'top is CompoundAssign') or return;
    is($ca->inputs()->[0]->value(), '//=', 'op is //=');
    is($ca->inputs()->[1]->value(), '$a', 'left is $a');
    is($ca->inputs()->[2]->value(), '$b', 'right is $b');
};

# ============================================================================
# L20 **= compound assignment
# ----------------------------------------------------------------------------
# perlop L1362: **= is in the assignment-family list.
# ============================================================================

subtest 'L20 **= produces CompoundAssign with op "**="' => sub {
    my $expr = parse_expr('$a **= $b');
    my $ca = isa_with_shape($expr, 'Chalk::IR::Node::CompoundAssign',
        'top is CompoundAssign') or return;
    is($ca->inputs()->[0]->value(), '**=', 'op is **=');
};

# ============================================================================
# L20 x= compound assignment (string repetition assignment)
# ----------------------------------------------------------------------------
# perlop L1362 lists x= in the assignment family. Probe shows Chalk's grammar
# does not currently accept x= — mark TODO with diagnostic.
# ============================================================================

subtest 'L20 x= produces CompoundAssign with op "x="' => sub {
    my $expr = parse_expr('$a x= $b');
    ok(defined($expr) && ref($expr) && $expr->isa('Chalk::IR::Node::CompoundAssign'),
        'top is CompoundAssign')
        or diag('  got shape: ' . shape_of($expr));
    is(ref($expr) ? $expr->inputs()->[0]->value() : '<undef>', 'x=',
        'op is x=');
};

# ============================================================================
# L19 (?:) right-associativity
# ----------------------------------------------------------------------------
# perlop L1322: ternary ?: is right-associative. So
#   $a ? $b : $c ? $d : $e
# parses as
#   $a ? $b : ($c ? $d : $e)
# = TernaryExpr($a, $b, TernaryExpr($c, $d, $e)).
#
# Source wrapped in parens so parse_expr's "my \$_ = ..." wrapper isn't
# a bare assignment that the ternary condition check would reject.
# ============================================================================

subtest 'L19 ?: is right-associative: $a ? $b : $c ? $d : $e' => sub {
    my $expr = parse_expr('($a ? $b : $c ? $d : $e)');
    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::TernaryExpr',
        'top is TernaryExpr') or return;
    is(shape_of($outer->inputs()->[0]), 'Const($a)',
        'outer condition is $a (right-assoc)');
    is(shape_of($outer->inputs()->[1]), 'Const($b)',
        'outer then-branch is $b');
    my $else_branch = $outer->inputs()->[2];
    ok(defined($else_branch) && ref($else_branch)
        && $else_branch->isa('Chalk::IR::Node::TernaryExpr'),
        'outer else-branch is the nested ternary (right-assoc)')
        or diag('  got shape: ' . shape_of($else_branch));
    is(ref($else_branch) && $else_branch->isa('Chalk::IR::Node::TernaryExpr')
        ? shape_of($else_branch->inputs()->[0]) : '<n/a>',
        'Const($c)', 'inner condition is $c');
};

# ============================================================================
# L19 (?:) vs L17 (||): || is TIGHTER (lower L-number)
# ----------------------------------------------------------------------------
# perlop: || at L17, ?: at L19 — || binds tighter. So
#   $a || $b ? $c : $d
# parses as
#   ($a || $b) ? $c : $d
# = TernaryExpr(Or($a, $b), $c, $d).
#
# Probe shows current Chalk produces this shape correctly (Or is the
# condition of TernaryExpr) — but the ternary then absorbs the surrounding
# "my \$_ = ..." VarDecl, so parse_expr returns undef. The shape inside the
# parenthesized form is correct.
# ============================================================================

subtest 'L19 vs L17: $a || $b ? $c : $d is TernaryExpr(Or($a,$b), $c, $d)' => sub {
    my $expr = parse_expr('($a || $b ? $c : $d)');
    my $tern = isa_with_shape($expr, 'Chalk::IR::Node::TernaryExpr',
        'top is TernaryExpr') or return;
    isa_with_shape($tern->inputs()->[0], 'Chalk::IR::Node::Or',
        'condition of TernaryExpr is Or (|| binds tighter than ?:)');
    is(shape_of($tern->inputs()->[1]), 'Const($c)', 'then-branch is $c');
    is(shape_of($tern->inputs()->[2]), 'Const($d)', 'else-branch is $d');
};

# ============================================================================
# L19 (?:) vs L20 (=): ?: is TIGHTER (lower L-number)
# ----------------------------------------------------------------------------
# perlop: ?: at L19, = at L20 — ternary binds tighter. So
#   $a = $b ? $c : $d
# parses as
#   $a = ($b ? $c : $d)
# = Assign($a, TernaryExpr($b, $c, $d)).
#
# This is the famous "ternary inverts assignment" footgun (see perlop L1340
# "Because this operator produces an assignable result, using assignments
# without parentheses will get you in trouble.").
#
# The precedence semiring enforces this: when '?' scans in a TernaryExpression,
# the accumulated condition level is checked and level>=100 (AssignmentExpression
# or nested TernaryExpression) is rejected.
# ============================================================================

subtest 'L19 vs L20: $a = $b ? $c : $d is Assign($a, TernaryExpr($b, $c, $d))' => sub {
    my $expr = parse_expr('($a = $b ? $c : $d)');
    my $is_assign = isa_with_shape($expr, 'Chalk::IR::Node::Assign',
        'top is Assign') or return;
    is($expr->left()->value(), '$a', 'left of Assign is $a');
    isa_with_shape($expr->right(), 'Chalk::IR::Node::TernaryExpr',
        'right of Assign is TernaryExpr (?: tighter than =)');
};

# ============================================================================
# L19 ?: without parens: $a = $b ? $c : $d parses as Assign($a, TernaryExpr)
# ----------------------------------------------------------------------------
# perlop L19 < L20: ternary binds tighter than assignment. So without parens,
# `$a = $b ? $c : $d` still parses as `$a = ($b ? $c : $d)` = Assign($a,
# TernaryExpr($b, $c, $d)). The scan-time check at '?' ensures assignment
# cannot become the condition of a ternary without parentheses.
# ============================================================================

subtest 'L19 ?: no-paren: $a = $b ? $c : $d parses as Assign($a, TernaryExpr($b,$c,$d))' => sub {
    my $expr = parse_expr('$a = $b ? $c : $d');
    ok(defined $expr, 'parse_expr returns defined IR for un-parenthesized form');
    my $is_assign = isa_with_shape($expr, 'Chalk::IR::Node::Assign',
        'top is Assign') or return;
    is($expr->left()->value(), '$a', 'left of Assign is $a');
    isa_with_shape($expr->right(), 'Chalk::IR::Node::TernaryExpr',
        'right of Assign is TernaryExpr');
};

# ============================================================================
# Assignable ternary: ($x ? $y : $z) = $w (lvalue ternary)
# ----------------------------------------------------------------------------
# perlop L1340-L1343: "The operator may be assigned to if both the 2nd and
# 3rd arguments are legal lvalues (meaning that you can assign to them):
# ($x_or_y ? $x : $y) = $z;"
#
# With explicit parens, this should produce Assign(TernaryExpr(...), $w).
# Probe shows current Chalk produces this correctly when parens are present.
# ============================================================================

subtest 'Lvalue ternary: ($x ? $y : $z) = 1 is Assign(TernaryExpr(...), 1)' => sub {
    my $expr = parse_expr('($x ? $y : $z) = 1');
    my $assign = isa_with_shape($expr, 'Chalk::IR::Node::Assign',
        'top is Assign') or return;
    isa_with_shape($assign->left(), 'Chalk::IR::Node::TernaryExpr',
        'left of Assign is TernaryExpr (lvalue ternary)');
    is($assign->right()->value(), '1', 'right of Assign is 1');
};

# ============================================================================
# L19 (?:) bilateral coverage
# ----------------------------------------------------------------------------
# These tests confirm ternary interacts correctly with other operators in both
# directions: ternary is looser than binary ops (they are tighter), and
# ternary is tighter than assignment (assignment is looser).
# ============================================================================

subtest 'L19 vs L8 (+): + binds tighter than ?: — $a + $b ? $c : $d is TernaryExpr(Add,c,d)' => sub {
    # + at L8 binds tighter than ?: at L19.
    # So `$a + $b ? $c : $d` = TernaryExpr(Add($a,$b), $c, $d).
    my $expr = parse_expr('$a + $b ? $c : $d');
    my $tern = isa_with_shape($expr, 'Chalk::IR::Node::TernaryExpr',
        'top is TernaryExpr') or return;
    isa_with_shape($tern->inputs()->[0], 'Chalk::IR::Node::Add',
        'condition is Add (+ binds tighter than ?:)');
    is(shape_of($tern->inputs()->[1]), 'Const($c)', 'then-branch is $c');
    is(shape_of($tern->inputs()->[2]), 'Const($d)', 'else-branch is $d');
};

subtest 'L19 vs L10 (&&): && binds tighter than ?: — $a && $b ? $c : $d is TernaryExpr(And,c,d)' => sub {
    # && at L10 binds tighter than ?: at L19.
    # So `$a && $b ? $c : $d` = TernaryExpr(And($a,$b), $c, $d).
    my $expr = parse_expr('$a && $b ? $c : $d');
    my $tern = isa_with_shape($expr, 'Chalk::IR::Node::TernaryExpr',
        'top is TernaryExpr') or return;
    isa_with_shape($tern->inputs()->[0], 'Chalk::IR::Node::And',
        'condition is And (&& binds tighter than ?:)');
    is(shape_of($tern->inputs()->[1]), 'Const($c)', 'then-branch is $c');
    is(shape_of($tern->inputs()->[2]), 'Const($d)', 'else-branch is $d');
};

subtest 'L19 ternary branches can contain + without parens' => sub {
    # The then/else branches of ternary accept binary expressions freely.
    # `$a ? $b + $c : $d - $e` = TernaryExpr($a, Add($b,$c), Sub($d,$e)).
    my $expr = parse_expr('$a ? $b + $c : $d');
    my $tern = isa_with_shape($expr, 'Chalk::IR::Node::TernaryExpr',
        'top is TernaryExpr') or return;
    is(shape_of($tern->inputs()->[0]), 'Const($a)', 'condition is $a');
    isa_with_shape($tern->inputs()->[1], 'Chalk::IR::Node::Add',
        'then-branch is Add (binary op inside ternary branch)');
    is(shape_of($tern->inputs()->[2]), 'Const($d)', 'else-branch is $d');
};

subtest 'L19 nested ternary three levels: $a ? $b : $c ? $d : $e ? $f : $g' => sub {
    # Three-level right-assoc chain:
    #   $a ? $b : ($c ? $d : ($e ? $f : $g))
    my $expr = parse_expr('($a ? $b : $c ? $d : $e ? $f : $g)');
    my $t1 = isa_with_shape($expr, 'Chalk::IR::Node::TernaryExpr',
        'top is TernaryExpr') or return;
    is(shape_of($t1->inputs()->[0]), 'Const($a)', 'outer condition is $a');
    is(shape_of($t1->inputs()->[1]), 'Const($b)', 'outer then is $b');
    my $t2 = isa_with_shape($t1->inputs()->[2], 'Chalk::IR::Node::TernaryExpr',
        'outer else is TernaryExpr (right-assoc level 2)') or return;
    is(shape_of($t2->inputs()->[0]), 'Const($c)', 'mid condition is $c');
    is(shape_of($t2->inputs()->[1]), 'Const($d)', 'mid then is $d');
    my $t3 = isa_with_shape($t2->inputs()->[2], 'Chalk::IR::Node::TernaryExpr',
        'mid else is TernaryExpr (right-assoc level 3)') or return;
    is(shape_of($t3->inputs()->[0]), 'Const($e)', 'inner condition is $e');
    is(shape_of($t3->inputs()->[1]), 'Const($f)', 'inner then is $f');
    is(shape_of($t3->inputs()->[2]), 'Const($g)', 'inner else is $g');
};

subtest 'L19 ternary in assignment RHS: $x = $a ? $b : $c is Assign($x, TernaryExpr)' => sub {
    # = at L20 is looser; ternary builds the RHS first.
    my $expr = parse_expr('$x = $a ? $b : $c');
    my $assign = isa_with_shape($expr, 'Chalk::IR::Node::Assign',
        'top is Assign') or return;
    is($assign->left()->value(), '$x', 'left of Assign is $x');
    isa_with_shape($assign->right(), 'Chalk::IR::Node::TernaryExpr',
        'right of Assign is TernaryExpr');
};

# ============================================================================
# L18 (..) vs L17 (||): || is TIGHTER (lower L-number)
# ----------------------------------------------------------------------------
# perlop L1108: "Range Operators ... The precedence is a little lower than
# || and &&." So .. is at L18, below L17 (||), and
#   $a || $b .. $c
# parses as
#   ($a || $b) .. $c
# = Range(Or($a, $b), $c).
#
# Probe shows current Chalk produces this shape correctly.
# ============================================================================

subtest 'L17 || tighter than L18 ..: $a || $b .. $c is Range(Or($a,$b), $c)' => sub {
    my $expr = parse_expr('$a || $b .. $c');
    my $range = isa_with_shape($expr, 'Chalk::IR::Node::Range',
        'top is Range') or return;
    isa_with_shape($range->left(), 'Chalk::IR::Node::Or',
        'left of Range is Or (|| binds tighter than ..)');
    is($range->right()->value(), '$c', 'right of Range is $c');
};

# ============================================================================
# L18 (..) basic shape and operator string
# ----------------------------------------------------------------------------
# perlop L1108: ".." is the range operator. Verify it produces a Range node
# carrying the .. token.
# ============================================================================

subtest 'L18 basic .. : 1 .. 10 is Range(1, 10)' => sub {
    my $expr = parse_expr('1 .. 10');
    my $range = isa_with_shape($expr, 'Chalk::IR::Node::Range',
        'top is Range') or return;
    is($range->op_str(), '..', 'op_str is ..');
    is($range->left()->value(), '1', 'left is 1');
    is($range->right()->value(), '10', 'right is 10');
};

# ============================================================================
# L18 (..) is non-associative — 1 .. 10 .. 100 should be a syntax error
# ----------------------------------------------------------------------------
# perlop precedence table line 146: ".." and "..." are nonassoc. Per real
# Perl, "1 .. 10 .. 100" is a syntax error.
#
# Probe shows current Chalk *silently parses* it as Range(Range(1,10), 100)
# — i.e., it accepts it as left-associative. Mark TODO; the assertion is
# that parse_expr should return undef (parse failure).
# ============================================================================

subtest 'L18 .. is non-associative: 1 .. 10 .. 100 should not parse' => sub {
    my $expr = parse_expr('1 .. 10 .. 100');
    ok(!defined $expr, 'chained .. should be a parse error per perlop nonassoc');
};

# ============================================================================
# L18 (...) flip-flop range — perlop says it behaves like ".." with
# different flip-flop semantics
# ----------------------------------------------------------------------------
# perlop L1134: "If you don't want it to test the right operand until the
# next evaluation, as in sed, just use three dots ('...') instead of two.
# In all other regards, '...' behaves just like '..' does."
#
# '...' in binary-expression context is the flip-flop range operator.
# The yada-yada placeholder ('...') is a bare statement, not a binary op,
# and is handled separately. BINOP_MAP maps '...' to Range so that
# expression-context '...' produces the same Range node class as '..'.
# The '..' vs '...' semantic distinction (lazy flip-flop vs eager range)
# is elided in the IR; a future FlipFlop typed node can restore it.
# ============================================================================

subtest 'L18 ... is the flip-flop range, not yada-yada: 1 ... 10 is Range' => sub {
    my $expr = parse_expr('1 ... 10');
    ok(defined($expr) && ref($expr) && $expr->isa('Chalk::IR::Node::Range'),
        'top is Range (flip-flop ...)')
        or diag('  got shape: ' . shape_of($expr));
};

# ============================================================================
# L20 vs L21 (,): assignment binds tighter than comma
# ----------------------------------------------------------------------------
# perlop: "=" at L20, "," at L21 — assignment binds tighter. So
#   $a = 1, 2
# parses as
#   ($a = 1), 2
# i.e., the comma is the statement-separator/list-builder *outside* the
# assignment.
#
# Probe shows Chalk currently treats the "," at this level as a *statement*
# separator: parsing `my \$_ = \$a = 1, 2;` produces TWO top-level
# statements — VarDecl(\$_, Assign(\$a, 1)) and Const(2). That is consistent
# with "= binds tighter than ," but the comma is being interpreted as a
# new-statement boundary rather than as L21 list-comma. parse_expr extracts
# only the first VarDecl's initializer, so we see Assign(\$a, 1).
# ============================================================================

subtest 'L20 = tighter than L21 ,: $a = 1, 2 -- = binds first' => sub {
    my $expr = parse_expr('$a = 1, 2');
    my $assign = isa_with_shape($expr, 'Chalk::IR::Node::Assign',
        'top is Assign (= bound before ,)') or return;
    is($assign->left()->value(), '$a', 'left of Assign is $a');
    is($assign->right()->value(), '1', 'right of Assign is 1');
};

# ============================================================================
# L20 control-flow keywords: last, next, redo
# ----------------------------------------------------------------------------
# perlop precedence table line 148: "right = += -= *= etc., goto last next
# redo dump" — these control-flow keywords sit at L20 right-associative.
#
# Probe shows that bare "last", "next", "redo" parse as Const("last"),
# Const("next"), Const("redo") when wrapped as expressions. With a label
# argument they parse as Call(Const("last"), [Const("LABEL")]). Verify the
# bare-keyword shape; the label form is covered in a separate subtest.
# ============================================================================

subtest 'L20 bare last: parses as Const("last")' => sub {
    my $expr = parse_expr('last');
    isa_with_shape($expr, 'Chalk::IR::Node::Constant',
        'top is Constant') or return;
    is($expr->value(), 'last', 'constant value is "last"');
};

subtest 'L20 bare next: parses as Const("next")' => sub {
    my $expr = parse_expr('next');
    isa_with_shape($expr, 'Chalk::IR::Node::Constant',
        'top is Constant') or return;
    is($expr->value(), 'next', 'constant value is "next"');
};

subtest 'L20 bare redo: parses as Const("redo")' => sub {
    my $expr = parse_expr('redo');
    isa_with_shape($expr, 'Chalk::IR::Node::Constant',
        'top is Constant') or return;
    is($expr->value(), 'redo', 'constant value is "redo"');
};

# ============================================================================
# L20 control-flow with label: last LABEL, goto LABEL
# ----------------------------------------------------------------------------
# perlop precedence table line 148: last/next/redo/goto/dump take an optional
# label. Probe shows Chalk emits these as Call nodes:
#   last LABEL → Call(Const("last"), [Const("LABEL")])
#   goto FOO   → Call(Const("goto"), [Const("FOO")])
# ============================================================================

subtest 'L20 last LABEL: Call(Const("last"), [Const("LABEL")])' => sub {
    my $expr = parse_expr('last LABEL');
    my $call = isa_with_shape($expr, 'Chalk::IR::Node::Call',
        'top is Call') or return;
    is($call->inputs()->[0]->value(), 'last', 'callee Const is "last"');
    my $args = $call->inputs()->[1];
    ok(ref($args) eq 'ARRAY' && @$args, 'has args') or return;
    is($args->[0]->value(), 'LABEL', 'arg is LABEL');
};

subtest 'L20 goto LABEL: Call(Const("goto"), [Const("LABEL")])' => sub {
    my $expr = parse_expr('goto FOO');
    my $call = isa_with_shape($expr, 'Chalk::IR::Node::Call',
        'top is Call') or return;
    is($call->inputs()->[0]->value(), 'goto', 'callee Const is "goto"');
    my $args = $call->inputs()->[1];
    ok(ref($args) eq 'ARRAY' && @$args, 'has args') or return;
    is($args->[0]->value(), 'FOO', 'arg is FOO');
};

# ============================================================================
# L20 (=) vs L8 (+): = is LOOSER, so addition binds before assignment
# ----------------------------------------------------------------------------
# perlop: + at L8, = at L20. Addition binds tighter. So
#   ($x = 5) + 10
# requires explicit parens to force the assignment-then-add ordering.
# Without parens, $x = 5 + 10 would parse as $x = (5 + 10).
# Verify the parenthesized form produces Add(Assign($x, 5), 10).
# ============================================================================

subtest 'L20 vs L8: ($x = 5) + 10 is Add(Assign($x, 5), 10)' => sub {
    my $expr = parse_expr('($x = 5) + 10');
    my $add = isa_with_shape($expr, 'Chalk::IR::Node::Add',
        'top is Add') or return;
    isa_with_shape($add->inputs()->[1], 'Chalk::IR::Node::Assign',
        'left of Add is Assign (parenthesized)');
    is($add->inputs()->[2]->value(), '10', 'right of Add is 10');
};

# ============================================================================
# Without parens: $x = 5 + 10 — L8 + binds before L20 =
# ----------------------------------------------------------------------------
# Verify the natural unparenthesized form: Assign($x, Add(5, 10)).
# ============================================================================

subtest 'L20 vs L8 unparenthesized: $x = 5 + 10 is Assign($x, Add(5, 10))' => sub {
    my $expr = parse_expr('$x = 5 + 10');
    my $assign = isa_with_shape($expr, 'Chalk::IR::Node::Assign',
        'top is Assign') or return;
    is($assign->left()->value(), '$x', 'left of Assign is $x');
    isa_with_shape($assign->right(), 'Chalk::IR::Node::Add',
        'right of Assign is Add (+ binds tighter than =)');
};

# ============================================================================
# Bilateral coverage: ternary `:` must reset the precedence accumulator so
# the else-branch can carry its own binary operators independent of the
# then-branch's. Mirror of the `?` reset for the condition→then boundary.
# ----------------------------------------------------------------------------
# Pre-fix, `1 ? 0 == 0 : 0 == 0;` failed because the BinaryExpression in
# the then-branch left level=7 in the precedence accumulator, and the
# scan at `:` propagated that level into the else-branch, breaking the
# parse of `0 == 0` on the else side. The fix adds a `:` reset alongside
# the `?` reset in Precedence._scan_multiply.
#
# Bilateral: same-class operator on BOTH branches (the discriminating case
# — same-class on one branch alone always worked because the other branch's
# `Atom` doesn't carry a precedence level).
# ============================================================================

subtest 'Ternary `:` resets accumulator — same-class bin-op on both branches' => sub {
    my @cases = (
        # (label, source, expected-IR-class for the whole expression)
        ['==',  '1 ? 0 == 0 : 0 == 0',           'Chalk::IR::Node::TernaryExpr'],
        ['+',   '1 ? 1 + 2 : 3 + 4',             'Chalk::IR::Node::TernaryExpr'],
        ['*',   '1 ? 1 * 2 : 3 * 4',             'Chalk::IR::Node::TernaryExpr'],
        ['eq',  '$a ? $b eq $c : $d eq $e',      'Chalk::IR::Node::TernaryExpr'],
        ['&&',  '$a ? $b && $c : $d && $e',      'Chalk::IR::Node::TernaryExpr'],
        # Mixed levels also must parse:
        ['+/*', '1 ? 1 + 2 : 3 * 4',             'Chalk::IR::Node::TernaryExpr'],
        ['==/&&', '$a ? $b == $c : $d && $e',    'Chalk::IR::Node::TernaryExpr'],
    );
    for my $case (@cases) {
        my ($label, $src, $cls) = $case->@*;
        my $expr = parse_expr("($src)");
        isa_with_shape($expr, $cls,
            "ternary with $label on both branches parses as TernaryExpr");
    }
};

done_testing;
