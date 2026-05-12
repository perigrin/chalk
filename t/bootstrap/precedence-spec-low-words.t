# ABOUTME: Conformance test for Perl low-precedence list/word ops per perlop.pod (Perl 5.42).
# ABOUTME: Covers L21 (, =>), L22 (rightward list operators), L23 (not), L24 (and), L25 (or xor).
#
# This file is a TDD spec: every subtest is derived from perlop.pod's
# documented precedence table, not from Chalk's PrecedenceTable.pm. Tests that
# fail on current Chalk are marked TODO; the TODO inventory is the
# Precedence-semiring work backlog for the low-precedence word-operator
# cluster.
#
# perlop.pod's relevant precedence levels (highest binding = lower number):
#
#     L20  right     = += -= *= etc., goto, last, next, redo, dump
#     L21  left      , =>
#     L22  nonassoc  list operators (rightward)
#     L23  right     not
#     L24  left      and
#     L25  left      or xor
#
# Per perlop:
#   - "=>" is a synonym for "," (with a left-side auto-quoting tokenizer
#     wrinkle that is not a precedence concern).
#   - "not" is "the equivalent of '!' except for the very low precedence."
#   - "and" is "equivalent to && except for the very low precedence."
#   - "or" is "equivalent to || except for it having very low precedence."
#   - "xor" is "equivalent to ^^ except for it having very low precedence.
#     It cannot short-circuit (of course)."
#   - On the right side of a list operator, "the comma has very low
#     precedence, such that it controls all comma-separated expressions
#     found there. The only operators with lower precedence are the logical
#     operators 'and', 'or', and 'not'..."

use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use PrecedenceSpecHelpers qw(parse_expr shape_of isa_with_shape);

use Chalk::IR::Node;
use Chalk::IR::Node::And;
use Chalk::IR::Node::Or;
use Chalk::IR::Node::Xor;
use Chalk::IR::Node::Not;
use Chalk::IR::Node::NumEq;
use Chalk::IR::Node::Assign;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::HashRef;
use Chalk::IR::Node::Constant;

# ============================================================================
# L23 (not) vs L13 (==): the load-bearing illustration of why "not" exists
# ----------------------------------------------------------------------------
# perlop: "Unary 'not' returns the logical negation of the expression to its
# right. It's the equivalent of '!' except for the very low precedence."
#
# So `not $a == $b` should bind as `not ($a == $b)` — Not(NumEq($a, $b)) —
# because not is L23, far looser than == at L13.
# Compare to `!$a == $b` which IS `(!$a) == $b` — NumEq(Not($a), $b) —
# because ! is L5, tighter than ==.
# ============================================================================

subtest 'L23 not is looser than L13 ==: not $a == $b is Not(NumEq($a,$b))' => sub {
    # perlop: "not" is L23, "==" is L13 (nonassoc). L23 is looser than L13,
    # so "not" binds last: `not $a == $b` groups as `not ($a == $b)`.
    # Contrast with `!$a == $b` where "!" is L5 (tighter than "=="),
    # giving `(!$a) == $b`.
    my $expr = parse_expr('not $a == $b');

    my $is_not = ref($expr) && $expr->isa('Chalk::IR::Node::Not');
    ok($is_not, 'top is Not') or do {
        diag('  got shape: ' . shape_of($expr));
        return;
    };
    # Not has op_text at inputs->[0], operand at inputs->[1].
    my $operand = $expr->inputs()->[1];
    isa_with_shape($operand, 'Chalk::IR::Node::NumEq',
        'operand of Not is NumEq');
};

subtest 'L5 ! is tighter than L13 ==: !$a == $b is NumEq(Not($a), $b) (baseline)' => sub {
    # Baseline / control: ! is L5, == is L13, so this groups as (!$a) == $b.
    # Confirms current parser treats ! correctly; the divergence above is
    # specific to "not".
    my $expr = parse_expr('!$a == $b');

    my $eq = isa_with_shape($expr, 'Chalk::IR::Node::NumEq',
        'top is NumEq') or return;
    # NumEq has op_text at inputs->[0], left at inputs->[1], right at inputs->[2].
    isa_with_shape($eq->inputs()->[1], 'Chalk::IR::Node::Not',
        'left of NumEq is Not');
    is($eq->inputs()->[2]->value(), '$b', 'right of NumEq is $b');
};

# ============================================================================
# L23 (not) bilateral coverage: not is tighter than and (L24) and or (L25)
# ----------------------------------------------------------------------------
# perlop: "not" is L23; "and" is L24, "or"/"xor" are L25. So "not" binds
# tighter than "and" and "or". `not $a and $b` must parse as (not $a) and $b,
# not as not ($a and $b). Same for `not $a or $b`.
# ============================================================================

subtest 'L23 not tighter than L24 and: not $a and $b is And(Not($a),$b)' => sub {
    # perlop: not at L23, and at L24 — not is tighter, so not $a and $b
    # groups as (not $a) and $b, not as not ($a and $b).
    my $expr = parse_expr('not $a and $b');

    my $and = isa_with_shape($expr, 'Chalk::IR::Node::And',
        'top is And') or return;
    isa_with_shape($and->inputs()->[1], 'Chalk::IR::Node::Not',
        'left of And is Not');
    is($and->inputs()->[2]->value(), '$b', 'right of And is $b');
};

subtest 'L23 not tighter than L25 or: not $a or $b is Or(Not($a),$b)' => sub {
    # perlop: not at L23, or at L25 — not is tighter, so not $a or $b
    # groups as (not $a) or $b, not as not ($a or $b).
    my $expr = parse_expr('not $a or $b');

    my $or = isa_with_shape($expr, 'Chalk::IR::Node::Or',
        'top is Or') or return;
    isa_with_shape($or->inputs()->[1], 'Chalk::IR::Node::Not',
        'left of Or is Not');
    is($or->inputs()->[2]->value(), '$b', 'right of Or is $b');
};

# ============================================================================
# L24 (and) tighter than L25 (or): $a or $b and $c is Or($a, And($b, $c))
# ----------------------------------------------------------------------------
# perlop: and at L24, or at L25; "and" binds tighter than "or" — same shape
# as `$a || $b && $c` from the standard ops, just with word-operator nodes.
# ============================================================================

subtest 'L24 and tighter than L25 or: $a or $b and $c is Or($a, And($b,$c))' => sub {
    my $expr = parse_expr('$a or $b and $c');

    my $or = isa_with_shape($expr, 'Chalk::IR::Node::Or',
        'top is Or') or return;
    # Or has op_text at inputs->[0], left at inputs->[1], right at inputs->[2].
    is($or->inputs()->[1]->value(), '$a', 'left of Or is $a');
    my $and = isa_with_shape($or->inputs()->[2], 'Chalk::IR::Node::And',
        'right of Or is And') or return;
    is($and->inputs()->[1]->value(), '$b', 'left of And is $b');
    is($and->inputs()->[2]->value(), '$c', 'right of And is $c');
};

subtest 'L25 or is left-associative: $a or $b or $c is Or(Or($a,$b),$c)' => sub {
    # perlop: "left  or xor" — left-associative grouping.
    my $expr = parse_expr('$a or $b or $c');

    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::Or',
        'top is Or') or return;
    isa_with_shape($outer->inputs()->[1], 'Chalk::IR::Node::Or',
        'left of outer Or is another Or (left-assoc)');
    is($outer->inputs()->[2]->value(), '$c', 'right of outer Or is $c');
};

subtest 'L24 and is left-associative: $a and $b and $c is And(And($a,$b),$c)' => sub {
    # perlop: "left  and"
    my $expr = parse_expr('$a and $b and $c');

    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::And',
        'top is And') or return;
    isa_with_shape($outer->inputs()->[1], 'Chalk::IR::Node::And',
        'left of outer And is another And (left-assoc)');
    is($outer->inputs()->[2]->value(), '$c', 'right of outer And is $c');
};

# ============================================================================
# L25 xor with or: both at L25, left-associative
# ----------------------------------------------------------------------------
# perlop groups xor with or at L25. Both are left-associative.
# `$a or $b xor $c` should bind left-to-right: Xor(Or($a, $b), $c).
# ============================================================================

subtest 'L25 xor and or are co-precedent, left-assoc: $a or $b xor $c' => sub {
    my $expr = parse_expr('$a or $b xor $c');

    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::Xor',
        'top is Xor (left-assoc with or)') or return;
    my $or = isa_with_shape($outer->inputs()->[1], 'Chalk::IR::Node::Or',
        'left of Xor is Or') or return;
    is($or->inputs()->[1]->value(), '$a', 'left of Or is $a');
    is($or->inputs()->[2]->value(), '$b', 'right of Or is $b');
    is($outer->inputs()->[2]->value(), '$c', 'right of Xor is $c');
};

subtest 'L25 xor produces an Xor node distinct from Or: $a xor $b' => sub {
    # xor must NOT degrade to Or — it's logical exclusive-or, semantically
    # distinct (and per perlop "cannot short-circuit, of course").
    my $expr = parse_expr('$a xor $b');

    my $xor = isa_with_shape($expr, 'Chalk::IR::Node::Xor',
        'top is Xor') or return;
    is($xor->inputs()->[1]->value(), '$a', 'left of Xor is $a');
    is($xor->inputs()->[2]->value(), '$b', 'right of Xor is $b');
};

# ============================================================================
# L21 (, =>): => is just a comma (precedence-wise)
# ----------------------------------------------------------------------------
# perlop: "the '=>' operator behaves exactly as the comma operator or list
# argument separator, according to context." (The auto-quoting of a bareword
# left operand is a tokenizer concern, not a precedence one.)
# ============================================================================

subtest 'L21 => parses identically to , in a parenthesized list' => sub {
    # Build the same list two ways and assert IR shape equivalence.
    my $with_fat   = parse_expr("('key', 'val')");
    my $with_comma = parse_expr("('key', 'val')");
    my $with_arrow = parse_expr("('key' => 'val')");

    isa_with_shape($with_arrow, 'Chalk::IR::Node::HashRef',
        '("key" => "val") is a HashRef-shaped list');
    isa_with_shape($with_comma, 'Chalk::IR::Node::HashRef',
        '("key", "val") is a HashRef-shaped list');
    is(shape_of($with_arrow), shape_of($with_comma),
        '=> and , produce identical IR shape');
};

# ============================================================================
# L21 (,) inside a parenthesized list: flat or left-nested?
# ----------------------------------------------------------------------------
# perlop documents "," as left-associative at L21. Many IRs flatten the
# n-ary list into a single sequence rather than encoding the
# left-associativity literally. We probe and assert what Chalk actually
# produces; this fixes the contract so future refactors notice if it
# changes.
# ============================================================================

subtest 'L21 , in a parenthesized list flattens to an n-ary HashRef child list' => sub {
    # Probed: (1, 2, 3) currently produces HashRef with arrayref child
    # [Const(1), Const(2), Const(3)] — flat, not nested. Lock that in.
    my $expr = parse_expr('(1, 2, 3)');

    my $hr = isa_with_shape($expr, 'Chalk::IR::Node::HashRef',
        'top is HashRef') or return;
    my $items = $hr->inputs()->[0];
    ok(ref($items) eq 'ARRAY', 'HashRef child is an arrayref of items')
        or do { diag('  got shape: ' . shape_of($expr)); return };
    is(scalar($items->@*), 3, 'three items in the list');
    is($items->[0]->value(), '1', 'item 0 is 1');
    is($items->[1]->value(), '2', 'item 1 is 2');
    is($items->[2]->value(), '3', 'item 2 is 3');
};

# ============================================================================
# L20 (=) tighter than L21 (,): assignment binds before comma
# ----------------------------------------------------------------------------
# perlop: = at L20, , at L21. So `$a = 1, 2` should be `($a = 1), 2`, not
# `$a = (1, 2)`. (Cross-cluster; included as a single rep test because the
# = vs , boundary is the load-bearing edge of L21.)
# ============================================================================

subtest 'L20 = tighter than L21 , : $a = 1, 2 is ($a = 1), 2' => sub {
    # Parse at statement level to see whether the trailing ", 2" attaches
    # to the assignment or hangs off the program. parse_expr wraps in
    # `my $_ = ...;` so we test the conceptual shape inside the wrapper:
    # `my $_ = $a = 1, 2;` — the `, 2` should NOT be inside the Assign.
    my $expr = parse_expr('$a = 1, 2');

    # Probed behavior: $a = 1, 2 inside `my $_ = ...;` parses as
    # Assign($a, 1) and the ", 2" becomes a sibling top-level statement.
    # parse_expr returns just the Assign initializer, so the test we
    # CAN assert here is: the initializer top is Assign, its right is 1.
    # The "trailing comma escapes the assignment" property is implicit.
    my $assign = isa_with_shape($expr, 'Chalk::IR::Node::Assign',
        'top is Assign (= binds tighter than ,)') or return;
    is($assign->inputs()->[1]->value(), '$a', 'lhs of Assign is $a');
    is($assign->inputs()->[2]->value(), '1', 'rhs of Assign is 1 (not a list)');
};

# ============================================================================
# L22 (rightward list operators) slurp commas to the right
# ----------------------------------------------------------------------------
# perlop: "On the right side of a list operator, the comma has very low
# precedence, such that it controls all comma-separated expressions found
# there." — i.e., `chmod 0755, $f1, $f2` should make the call take all
# three args.
# ============================================================================

subtest 'L22 rightward chmod slurps comma list: chmod 0755, $f1, $f2' => sub {
    my $expr = parse_expr('chmod 0755, $f1, $f2');

    my $call = isa_with_shape($expr, 'Chalk::IR::Node::Call',
        'top is Call (chmod)') or return;

    TODO: {
        local $TODO = 'List operator inside `my $_ = ...;` only slurps first arg; trailing , falls outside';
        is($call->name(), 'chmod', 'callee is chmod');
        my $args = $call->inputs()->[1];
        my $argc = (ref($args) eq 'ARRAY') ? scalar($args->@*) : 0;
        is($argc, 3, 'chmod has three args');
        is(($args && $args->[0] ? $args->[0]->value() : undef), '0755', 'arg 0 is 0755');
        is(($args && $args->[1] ? $args->[1]->value() : undef), '$f1',  'arg 1 is $f1');
        is(($args && $args->[2] ? $args->[2]->value() : undef), '$f2',  'arg 2 is $f2');
    }
};

subtest 'L22 rightward sort slurps comma list: sort $a, $b, $c' => sub {
    my $expr = parse_expr('sort $a, $b, $c');

    my $call = isa_with_shape($expr, 'Chalk::IR::Node::Call',
        'top is Call (sort)') or return;

    TODO: {
        local $TODO = 'List operator inside `my $_ = ...;` only slurps first arg; trailing , falls outside';
        is($call->name(), 'sort', 'callee is sort');
        my $args = $call->inputs()->[1];
        my $argc = (ref($args) eq 'ARRAY') ? scalar($args->@*) : 0;
        is($argc, 3, 'sort has three args');
    }
};

subtest 'L22 rightward reverse slurps comma list: reverse 1, 2, 3' => sub {
    my $expr = parse_expr('reverse 1, 2, 3');

    my $call = isa_with_shape($expr, 'Chalk::IR::Node::Call',
        'top is Call (reverse)') or return;

    TODO: {
        local $TODO = 'List operator inside `my $_ = ...;` only slurps first arg; trailing , falls outside';
        is($call->name(), 'reverse', 'callee is reverse');
        my $args = $call->inputs()->[1];
        my $argc = (ref($args) eq 'ARRAY') ? scalar($args->@*) : 0;
        is($argc, 3, 'reverse has three args');
    }
};

# ============================================================================
# L21 (,) tighter than L25 (or): comma binds before `or`
# ----------------------------------------------------------------------------
# perlop: , at L21, or at L25 — comma is tighter. So inside a list-operator
# call argument like `print 1, 2 or die`, the comma gathers `1, 2` into the
# print-call's args, and `or die` binds the *result of the call* against
# `die`, giving `(print 1, 2) or die`.
#
# Probed: Chalk parses `print(1, 2) or die` (with explicit parens!) as
# `print(1, (2 or die))` — i.e. `or` binds tighter than `,`, which is
# backwards from perlop.
# ============================================================================

subtest 'L25 or vs L21 , with parenthesized call: print(1, 2) or die is Or(print(1,2), die)' => sub {
    # Use explicit parens to factor out the L22 list-operator slurping
    # question; this isolates the L21-vs-L25 comparison. The parenthesized
    # call makes (1, 2) clearly the call's arg list, then `or` binds the
    # call-result against `die`. Probed: this works correctly inside the
    # `my $_ = ...` wrapper.
    my $expr = parse_expr('print(1, 2) or die');

    my $or = isa_with_shape($expr, 'Chalk::IR::Node::Or',
        'top is Or (or binds the call-result with die)') or return;
    my $call = isa_with_shape($or->inputs()->[1], 'Chalk::IR::Node::Call',
        'left of Or is Call (print)') or return;
    is($call->name(), 'print', 'callee is print');
    my $args = $call->inputs()->[1];
    ok(ref($args) eq 'ARRAY', 'print has args arrayref') or return;
    is(scalar($args->@*), 2, 'print has two args (1 and 2)');
    is($args->[0]->value(), '1', 'arg 0 is 1');
    is($args->[1]->value(), '2', 'arg 1 is 2');
    is($or->inputs()->[2]->value(), 'die', 'right of Or is die');
};

# ============================================================================
# L21 (,) tighter than L25 (or) inside an unparenthesized list-operator tail
# ----------------------------------------------------------------------------
# perlop: `print 1, 2 or die` should parse as `(print 1, 2) or die`. This
# combines L22 (list-operator-rightward slurps commas) with L25 (`or` binds
# below comma). Both ingredients have known issues when expressed inside the
# `my $_ = ...` wrapper, so this is a TODO.
# ============================================================================

subtest 'L21 , tighter than L25 or inside list-op tail: print 1, 2 or die' => sub {
    my $expr = parse_expr('print 1, 2 or die');

    TODO: {
        local $TODO = 'List operator slurping inside `my $_ = ...;` is broken; , vs or boundary not enforced';
        my $is_or = ref($expr) && $expr->isa('Chalk::IR::Node::Or');
        ok($is_or, 'top is Or (or binds the call-result with die)');
        my $call_node = $is_or ? $expr->inputs()->[1] : undef;
        my $is_call = ref($call_node) && $call_node->isa('Chalk::IR::Node::Call');
        ok($is_call, 'left of Or is Call (print)');
        is(($is_call ? $call_node->name() : undef), 'print', 'callee is print');
        my $args = $is_call ? $call_node->inputs()->[1] : undef;
        my $argc = (ref($args) eq 'ARRAY') ? scalar($args->@*) : 0;
        is($argc, 2, 'print has two args (1 and 2)');
    }
};

# ============================================================================
# Common idiom: open(F, $f) or die
# ----------------------------------------------------------------------------
# This is the canonical "or die" pattern. With explicit parens around the
# call, the L25 `or` clearly applies to the whole call — and the parser
# does get this right (probed at statement level). Inside `my $_ = ...;`
# we should still see Or(Call(open, [F, $f]), die).
# ============================================================================

subtest 'L25 or with parenthesized list operator: open(F, $f) or die' => sub {
    my $expr = parse_expr('open(F, $f) or die');

    my $or = isa_with_shape($expr, 'Chalk::IR::Node::Or',
        'top is Or') or return;
    my $call = isa_with_shape($or->inputs()->[1], 'Chalk::IR::Node::Call',
        'left of Or is Call (open)') or return;
    is($call->name(), 'open', 'callee is open');
    is($or->inputs()->[2]->value(), 'die', 'right of Or is die');
};

done_testing;
