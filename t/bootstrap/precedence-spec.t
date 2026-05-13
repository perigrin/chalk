# ABOUTME: Conformance test for Perl operator precedence per perlop.pod (Perl 5.42).
# ABOUTME: Each subtest cites the perlop level pair and asserts IR shape; TODO = current gap.
#
# This file is a TDD spec: every subtest is derived from perlop.pod's
# documented precedence table, not from Chalk's PrecedenceTable.pm. Tests that
# fail on current Chalk are marked TODO; the TODO inventory is the
# Precedence-semiring work backlog.
#
# perlop.pod's precedence table (Perl 5.42, highest to lowest):
#
#     L1   left      terms and list operators (leftward)
#     L2   left      ->
#     L3   nonassoc  ++ --
#     L4   right     **
#     L5   right     ! ~ ~. \ and unary + and -
#     L6   left      =~ !~
#     L7   left      * / % x
#     L8   left      + - .
#     L9   left      << >>
#     L10  nonassoc  named unary operators (defined, exists, ref, scalar, ...)
#     L11  nonassoc  isa
#     L12  chained   < > <= >= lt gt le ge
#     L13  chain/na  == != eq ne <=> cmp ~~
#     L14  left      & &.
#     L15  left      | |. ^ ^.
#     L16  left      &&
#     L17  left      || ^^ //
#     L18  nonassoc  .. ...
#     L19  right     ?:
#     L20  right     = += -= *= etc., goto, last, next, redo, dump
#     L21  left      , =>
#     L22  nonassoc  list operators (rightward)
#     L23  right     not
#     L24  left      and
#     L25  left      or xor
#
# Lower number = tighter binding. Tests below cite this table by L-number.
#
# ## Coverage discipline
#
# When adding subtests for a new precedence level, include AT LEAST one test
# against operators on each side of the new level (one tighter, one looser).
# A single-direction test can pass even when the level is misnumbered, because
# the wrong number is still numerically defined and compares correctly in one
# direction. See docs/plans/2026-05-11-step2-second-blocker.md for an example
# of where this discipline would have prevented a two-rollback cycle.

use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::Program;
use Chalk::IR::Node;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;
use Chalk::IR::Node::Power;
use Chalk::IR::Node::And;
use Chalk::IR::Node::Or;
use Chalk::IR::Node::Not;
use Chalk::IR::Node::Negate;
use Chalk::IR::Node::Defined;
use Chalk::IR::Node::Subscript;
use Chalk::IR::Node::PostfixDeref;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::VarDecl;

# === Build the Perl grammar pipeline once ===

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR') or BAIL_OUT('grammar build failed');

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::PrecSpec/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $grammar = Chalk::Grammar::Perl::PrecSpec::grammar();
ok(defined $grammar, 'grammar loaded');

# === Test helpers ===

# Parse a source string, return the top-level expression IR for `my $x = EXPR;`.
# We wrap the test expression in a `my $_ = ...;` declaration so it's a
# well-formed statement; the helper then unwraps the VarDecl and returns the
# initializer expression IR.
sub parse_expr($source) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $stmt = "my \$_ = $source;";
    my $parser = build_perl_ir_parser($grammar, start => 'Program');
    my $result = eval { $parser->parse_value($stmt) };
    return undef if $@ || !defined $result || $result->is_zero();
    my $ir = $result->extract();
    return undef unless $ir isa Chalk::IR::Program;
    my $stmts = $ir->other_stmts();
    return undef unless $stmts && $stmts->@*;
    my $vardecl = $stmts->[0];
    return undef unless $vardecl isa Chalk::IR::Node::VarDecl;
    return $vardecl->inputs()->[1];
}

# A small structural-shape walker. Pass a tree of expected types/values:
#   ['Chalk::IR::Node::Add', '*', [...]]    means: type, optional op-string, optional children
# Returns (ok, msg).
sub shape_of($node) {
    return 'undef' unless defined $node;
    return 'ARRAY[' . join(',', map { shape_of($_) } $node->@*) . ']' if ref($node) eq 'ARRAY';
    return "SCALAR($node)" unless ref($node);
    my $cls = ref($node);
    if ($node isa Chalk::IR::Node::Constant) {
        return "Const(" . ($node->value() // '<undef>') . ")";
    }
    my @children;
    if ($node->can('inputs') && defined $node->inputs()) {
        @children = map { shape_of($_) } $node->inputs()->@*;
    }
    my $short = $cls =~ s/^Chalk::IR::Node:://r;
    return @children ? "$short(" . join(',', @children) . ")" : $short;
}

# Convenience: assert that a node is an instance of $type and return it (or
# fail with a diagnostic showing the actual shape).
sub isa_with_shape($node, $type, $label) {
    if (ref($node) && $node->isa($type)) {
        pass($label);
        return $node;
    }
    fail($label);
    diag("  expected isa $type");
    diag("  got shape: " . shape_of($node));
    return undef;
}

# ============================================================================
# L4 (**) right-associativity, baseline check
# ----------------------------------------------------------------------------
# perlop: "right ** "  — exponent is right-associative, so $a ** $b ** $c is
# $a ** ($b ** $c), not ($a ** $b) ** $c.
# ============================================================================

subtest 'L4 ** is right-associative: $a ** $b ** $c is $a ** ($b ** $c)' => sub {
    my $expr = parse_expr('$a ** $b ** $c');
    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::Power',
        'top is Power') or return;
    is($outer->inputs()->[1]->value(), '$a', 'outer left is $a');
    isa_with_shape($outer->inputs()->[2], 'Chalk::IR::Node::Power',
        'outer right is another Power (right-assoc)');
};

# ============================================================================
# L7 (*) tighter than L8 (+), baseline check
# ----------------------------------------------------------------------------
# perlop: * at L7, + at L8 — multiplication binds tighter than addition.
# 2 + 3 * 4 should be 2 + (3 * 4), giving Add(2, Multiply(3, 4)).
# ============================================================================

subtest 'L7 * tighter than L8 +: 2 + 3 * 4 is Add(2, Multiply(3,4))' => sub {
    my $expr = parse_expr('2 + 3 * 4');
    my $add = isa_with_shape($expr, 'Chalk::IR::Node::Add',
        'top is Add') or return;
    is($add->inputs()->[1]->value(), '2', 'left of Add is 2');
    my $mul = isa_with_shape($add->inputs()->[2], 'Chalk::IR::Node::Multiply',
        'right of Add is Multiply') or return;
    is($mul->inputs()->[1]->value(), '3', 'left of Multiply is 3');
    is($mul->inputs()->[2]->value(), '4', 'right of Multiply is 4');
};

subtest 'L8 - is left-associative: 2 - 3 - 4 is (2 - 3) - 4' => sub {
    my $expr = parse_expr('2 - 3 - 4');
    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::Subtract',
        'top is Subtract') or return;
    isa_with_shape($outer->inputs()->[1], 'Chalk::IR::Node::Subtract',
        'left of outer Subtract is another Subtract (left-assoc)');
    is($outer->inputs()->[2]->value(), '4', 'right of outer Subtract is 4');
};

# ============================================================================
# L16 (&&) tighter than L17 (||), baseline check
# ----------------------------------------------------------------------------
# perlop: && at L16, || at L17 — && binds tighter than ||.
# $a || $b && $c should be $a || ($b && $c), giving Or($a, And($b, $c)).
# ============================================================================

subtest 'L16 && tighter than L17 ||: $a || $b && $c is Or($a, And($b,$c))' => sub {
    my $expr = parse_expr('$a || $b && $c');
    my $or = isa_with_shape($expr, 'Chalk::IR::Node::Or',
        'top is Or') or return;
    is($or->inputs()->[1]->value(), '$a', 'left of Or is $a');
    my $and = isa_with_shape($or->inputs()->[2], 'Chalk::IR::Node::And',
        'right of Or is And') or return;
    is($and->inputs()->[1]->value(), '$b', 'left of And is $b');
    is($and->inputs()->[2]->value(), '$c', 'right of And is $c');
};

# ============================================================================
# L5 (unary !) tighter than L7-L8 (arithmetic), baseline check
# ----------------------------------------------------------------------------
# perlop: ! at L5, * at L7 — unary ! binds tighter than multiplication.
# !$x * 2 should be (!$x) * 2 = Multiply(Not($x), 2).
# ============================================================================

subtest 'L5 ! tighter than L7 *: !$x * 2 is Multiply(Not($x), 2)' => sub {
    my $expr = parse_expr('!$x * 2');
    my $mul = isa_with_shape($expr, 'Chalk::IR::Node::Multiply',
        'top is Multiply') or return;
    isa_with_shape($mul->inputs()->[1], 'Chalk::IR::Node::Not',
        'left of Multiply is Not');
    is($mul->inputs()->[2]->value(), '2', 'right of Multiply is 2');
};

# ============================================================================
# L2 (->) cluster: the load-bearing precedence-inversion gap
# ----------------------------------------------------------------------------
# perlop: -> at L2 (very high precedence, just below terms). Postfix deref,
# subscript, and method call all use ->. This level is currently MISSING from
# Chalk::Grammar::Perl::PrecedenceTable, which is why the
# subscript_over_builtin / subscript_over_unary / method_over_deref walker
# branches exist as workarounds.
#
# Every test below currently fails or is workaround-corrected by the walker.
# When PrecedenceTable.pm grows L2 entries and the Precedence semiring
# disambiguates -> against L5/L10/L20, these tests should pass directly.
# ============================================================================

subtest 'L2 (->) tighter than L10 (named unary "defined"): defined $h{key}' => sub {
    # perlop: -> at L2 (subscript), defined at L10. L2 binds tighter, so the
    # subscript groups first: defined($h{key}) = Defined(Subscript($h, key)).
    # Precedence is now correct: defined wraps the Subscript.
    # Remaining gap: Actions.pm emits Call(defined, [Subscript]) not
    # Chalk::IR::Node::Defined — a separate IR-type mapping issue.
    my $expr = parse_expr('defined $h{key}');

    TODO: {
        local $TODO = 'defined emits Call not Chalk::IR::Node::Defined; IR-type mapping gap in Actions.pm';
        my $defined = isa_with_shape($expr, 'Chalk::IR::Node::Defined',
            'top is Defined') or return;
        isa_with_shape($defined->inputs()->[0], 'Chalk::IR::Node::Subscript',
            'operand of Defined is Subscript');
    }
};

subtest 'L2 (->) tighter than L10 ("defined") via arrow subscript: defined $h->{key}' => sub {
    # Same as above but with the explicit arrow form: $h->{key}.
    # Precedence is now correct: defined wraps the Subscript.
    # Remaining gap: Actions.pm emits Call(defined, [Subscript]) not
    # Chalk::IR::Node::Defined — a separate IR-type mapping issue.
    my $expr = parse_expr('defined $h->{key}');

    TODO: {
        local $TODO = 'defined emits Call not Chalk::IR::Node::Defined; IR-type mapping gap in Actions.pm';
        my $defined = isa_with_shape($expr, 'Chalk::IR::Node::Defined',
            'top is Defined') or return;
        isa_with_shape($defined->inputs()->[0], 'Chalk::IR::Node::Subscript',
            'operand of Defined is Subscript');
    }
};

subtest 'L2 (->) tighter than L10 ("exists"): exists $h{key}' => sub {
    # perlop: -> at L2 (subscript), exists at L10. The subscript groups first:
    # exists($h{key}) — the named-unary grammar produces a Call node
    # with name "exists"; the assertion is that its argument is Subscript.
    my $expr = parse_expr('exists $h{key}');

    # exists is emitted as Call(builtin, "exists", [Subscript(...)])
    my $call = isa_with_shape($expr, 'Chalk::IR::Node::Call',
        'top is Call (exists builtin)') or return;
    is($call->name(), 'exists', 'callee is exists');
    my $args = $call->inputs()->[1];
    ok(ref($args) eq 'ARRAY' && @$args, 'has args') or return;
    isa_with_shape($args->[0], 'Chalk::IR::Node::Subscript',
        'first arg is Subscript');
};

subtest 'L2 (->) tighter than L5 (unary !): !$x->{key}' => sub {
    # perlop: -> at L2, ! at L5. Subscript binds tighter than negation:
    # !($x->{key}) = Not(Subscript($x, key)).
    my $expr = parse_expr('!$x->{key}');

    my $not = isa_with_shape($expr, 'Chalk::IR::Node::Not',
        'top is Not') or return;
    isa_with_shape($not->inputs()->[1], 'Chalk::IR::Node::Subscript',
        'operand of Not is Subscript');
};

subtest 'L2 (->) tighter than L5 (unary !) without arrow: !$h{key}' => sub {
    # Same precedence pair without the explicit arrow. Source: !$h{key}
    # Expected: Not(Subscript($h, key)).
    my $expr = parse_expr('!$h{key}');

    my $not = isa_with_shape($expr, 'Chalk::IR::Node::Not',
        'top is Not') or return;
    isa_with_shape($not->inputs()->[1], 'Chalk::IR::Node::Subscript',
        'operand of Not is Subscript');
};

subtest 'L2 (->) tighter than L5 (unary -): -$x->{key}' => sub {
    # perlop: -> at L2, unary - at L5. Subscript binds tighter:
    # -($x->{key}) = Negate(Subscript($x, key)).
    my $expr = parse_expr('-$x->{key}');

    my $neg = isa_with_shape($expr, 'Chalk::IR::Node::Negate',
        'top is Negate') or return;
    isa_with_shape($neg->inputs()->[1], 'Chalk::IR::Node::Subscript',
        'operand of Negate is Subscript');
};

# ============================================================================
# Bilateral L5 coverage: operator tighter than L5 (subscript) and looser
# ----------------------------------------------------------------------------
# Per coverage discipline: test both directions of L5 to catch future
# numbering mistakes. L2 subscript is tighter (tested above); L8 + and L16
# && are looser. Both must NOT be absorbed into the unary operand.
#
# B::Concise oracle:
#   `!$x + 1`   → not[$x] then add — so Add(Not($x), 1): ! tighter than +
#   `!$a && $b` → not[$a] then or(other) — so And(Not($a), $b): ! tighter than &&
# ============================================================================

subtest 'L5 ! tighter than L8 +: !$x + 1 is Add(Not($x), 1)' => sub {
    # perlop: ! at L5, + at L8. Unary ! binds tighter than addition.
    # B::Concise: `!$x + 1` → not then add → Add(Not($x), 1).
    my $expr = parse_expr('!$x + 1');

    my $add = isa_with_shape($expr, 'Chalk::IR::Node::Add',
        'top is Add') or return;
    isa_with_shape($add->inputs()->[1], 'Chalk::IR::Node::Not',
        'left of Add is Not');
    is($add->inputs()->[2]->value(), '1', 'right of Add is 1');
};

subtest 'L5 ! tighter than L16 &&: !$a && $b is And(Not($a), $b)' => sub {
    # perlop: ! at L5, && at L16. Unary ! binds tighter than logical and.
    # B::Concise: `!$a && $b` → not[$a] then and-or tree → And(Not($a), $b).
    my $expr = parse_expr('!$a && $b');

    my $and = isa_with_shape($expr, 'Chalk::IR::Node::And',
        'top is And') or return;
    isa_with_shape($and->inputs()->[1], 'Chalk::IR::Node::Not',
        'left of And is Not');
    is($and->inputs()->[2]->value(), '$b', 'right of And is $b');
};

subtest 'L2 (->) chains: method-then-deref: $obj->method()->@*' => sub {
    # perlop: -> at L2, both method-call and postfix-deref are at L2 — they
    # group left-to-right within the level. So $obj->method()->@* binds as
    # ($obj->method())->@* = PostfixDeref(Call($obj, method, []), @).
    #
    # Root cause: 2026-05-12 investigation found this is NOT a chart-level
    # ambiguity — the grammar admits exactly one derivation for the full
    # span (PostfixDeref ends with /@\*/, MethodCall ends with /\)/, they
    # cannot both match the input). The wrong shape is produced by
    # _push_deref_inward in Actions.pm, which unconditionally peels MethodCall
    # wrappers — including the case where MethodCall is the legitimate target
    # of ->@*. The walker's method_over_deref branch then undoes the damage
    # post-parse. The fix is to gate the MethodCall-peel branch in
    # _push_deref_inward to fire only when the MethodCall's invocant is
    # itself a peelable wrapper (BuiltinCall/Return/Unwind).
    my $expr = parse_expr('$obj->method()->@*');

    my $deref = isa_with_shape($expr, 'Chalk::IR::Node::PostfixDeref',
        'top is PostfixDeref') or return;
    is($deref->sigil(), '@', 'sigil is @');
    my $call = isa_with_shape($deref->inputs()->[0], 'Chalk::IR::Node::Call',
        'inner is Call (method)') or return;
    is($call->dispatch_kind(), 'method', 'dispatch_kind is method');
};

subtest 'L2 (->) chains: subscript-then-deref: $obj->{key}->@*' => sub {
    # perlop: both subscript and postfix-deref at L2; left-to-right so
    # ($obj->{key})->@* = PostfixDeref(Subscript($obj, key), @).
    # Already produces the correct shape via the Precedence semiring's
    # PostfixExpression level=-2 rejection of invalid subscript targets.
    my $expr = parse_expr('$obj->{key}->@*');

    my $deref = isa_with_shape($expr, 'Chalk::IR::Node::PostfixDeref',
        'top is PostfixDeref') or return;
    isa_with_shape($deref->inputs()->[0], 'Chalk::IR::Node::Subscript',
        'inner is Subscript');
};

subtest 'L2 (->) chains: deref-then-method: $obj->@*->method()' => sub {
    # perlop: $obj->@* deref first (L2, left-to-right), then ->method() on
    # the result. B::Concise oracle: rv2av then entersub (method on array).
    # Correct shape: Call(PostfixDeref($obj, @), method, []).
    # Root cause gap: _fix_postfix_chain.method_over_deref unconditionally
    # rewrites MethodCall(PostfixDeref(X,S)) → PostfixDeref(MethodCall(X),S),
    # which is wrong when the source is deref-then-method rather than
    # method-then-deref. Both cases produce the same pre-walker IR shape and
    # cannot be distinguished post-parse without source position information.
    my $expr = parse_expr('$obj->@*->method()');

    TODO: {
        local $TODO = 'L2 deref-then-method: walker method_over_deref branch over-applies; needs source-position gating';
        my $call = isa_with_shape($expr, 'Chalk::IR::Node::Call',
            'top is Call (method)') or return;
        is($call->dispatch_kind(), 'method', 'dispatch_kind is method');
        isa_with_shape($call->inputs()->[0], 'Chalk::IR::Node::PostfixDeref',
            'invocant is PostfixDeref');
    }
};

subtest 'L2 (->) chains: deref-then-subscript: $obj->@*[0]' => sub {
    # Postfix-deref-array-slice: $obj->@*[0] is an array slice over the deref.
    # perlop / postfixderef.t treats this as a single postfix operation.
    # Expected: a PostfixDeref node carrying both the sigil and the slice.
    my $expr = parse_expr('$obj->@[0]');

    # No TODO: this may already work via the grammar alternative for ->@[idx].
    my $deref = isa_with_shape($expr, 'Chalk::IR::Node::PostfixDeref',
        'top is PostfixDeref (with index)');
};

# ============================================================================
# Stacked precedence inversions: !exists $h{key}
# ----------------------------------------------------------------------------
# perlop: subscript at L2, exists at L10, ! at L5.
# Binding order from tightest: L2 (subscript) → L5 (!) → L10 (exists)?
# No — wait, ! is at L5 which is TIGHTER than L10 (exists).
#
# Per perlop: `!exists $h{key}` parses as `!(exists($h{key}))`.
# That's because:
#   - subscript binds first (L2): $h{key}
#   - exists is a named unary operator (L10) that takes the subscript: exists($h{key})
#   - ! (L5) is tighter than L10 — but L10 named-unaries are *terms* to L5's
#     unary-operator-or-list, so ! applies to the result of the named unary call.
#
# Why does ! apply to exists() rather than ! binding tighter to $h?
# Because perlop says "named unary operators" (exists, defined, etc.) are
# treated as if they had the precedence of a function call — they "bind" to
# their entire argument expression at L10's level. So when we see
# `! exists $h{key}`, the parser sees:
#   - `exists $h{key}` as a single L10 expression equal to a function call
#   - `!` as L5 unary applied to that L10 expression's result
#
# Expected IR: Not(Defined-equivalent-Call(exists, [Subscript($h, key)]))
# Currently: Subscript(Not(Call(exists, [$h])), key) — both inversions present.
# ============================================================================

subtest '!exists $h{key} parses as Not(Exists(Subscript($h, key)))' => sub {
    # perlop: subscript at L2, exists at L10, ! at L5.
    # Binding: subscript first (L2), then exists wraps it (L10 named-unary),
    # then ! applies to the result. Precedence semiring now handles all three.
    my $expr = parse_expr('!exists $h{key}');

    my $not = isa_with_shape($expr, 'Chalk::IR::Node::Not',
        'top is Not') or return;
    my $call = isa_with_shape($not->inputs()->[1], 'Chalk::IR::Node::Call',
        'operand of Not is Call (exists)') or return;
    is($call->name(), 'exists', 'callee is exists');
    my $args = $call->inputs()->[1];
    ok(ref($args) eq 'ARRAY' && @$args, 'exists has args') or return;
    isa_with_shape($args->[0], 'Chalk::IR::Node::Subscript',
        'arg of exists is Subscript');
};

subtest '!defined $h{key} parses as Not(Defined(Subscript($h, key)))' => sub {
    # Precedence is now correct: ! wraps the defined-call which wraps the subscript.
    # Partial pass: Not(Call(defined, [Subscript])) — top-level Not is correct.
    # Remaining gap: Actions.pm emits Call(defined, ...) not Chalk::IR::Node::Defined.
    my $expr = parse_expr('!defined $h{key}');

    my $not = isa_with_shape($expr, 'Chalk::IR::Node::Not',
        'top is Not') or return;
    TODO: {
        local $TODO = 'defined emits Call not Chalk::IR::Node::Defined; IR-type mapping gap in Actions.pm';
        my $defined = isa_with_shape($not->inputs()->[1], 'Chalk::IR::Node::Defined',
            'operand of Not is Defined') or return;
        isa_with_shape($defined->inputs()->[0], 'Chalk::IR::Node::Subscript',
            'operand of Defined is Subscript');
    }
};

# ============================================================================
# L2 (->) chains across line breaks (mined from Perl's t/op/postfixderef.t)
# ----------------------------------------------------------------------------
# perl's own tests exercise these patterns; we encode the IR shape we expect.
# ============================================================================

subtest '$ref->[2]->[0] chained subscripts: Subscript(Subscript($ref, 2), 0)' => sub {
    # From perl t/op/postfixderef.t line 84.
    my $expr = parse_expr('$ref->[2]->[0]');

    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::Subscript',
        'top is Subscript') or return;
    isa_with_shape($outer->inputs()->[0], 'Chalk::IR::Node::Subscript',
        'inner is Subscript');
};

subtest '$ref->[2][0] chained subscripts (no arrow elision)' => sub {
    # From perl t/op/postfixderef.t line 80. Same shape as above; the second
    # arrow is elidable per perlop.
    my $expr = parse_expr('$ref->[2][0]');

    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::Subscript',
        'top is Subscript') or return;
    isa_with_shape($outer->inputs()->[0], 'Chalk::IR::Node::Subscript',
        'inner is Subscript');
};

subtest '$refref->{"key"}[2][0] mixed hash/array chain' => sub {
    # From perl t/op/postfixderef.t line 93.
    my $expr = parse_expr('$refref->{"key"}[2][0]');

    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::Subscript',
        'outermost is Subscript') or return;
    my $mid = isa_with_shape($outer->inputs()->[0], 'Chalk::IR::Node::Subscript',
        'middle is Subscript') or return;
    isa_with_shape($mid->inputs()->[0], 'Chalk::IR::Node::Subscript',
        'innermost is Subscript');
};

# ============================================================================
# Bilateral L10 named-unary coverage: operators tighter and looser than L10
# ----------------------------------------------------------------------------
# Per docs/plans/2026-05-11-step2-second-blocker.md "Open question": the
# original L2-vs-L10 cluster tested only one direction. These tests cover
# both sides of L10 to catch future numbering mistakes.
#
# B::Concise oracle used to establish expected grouping for each expression.
# Chalk emits Call nodes for named-unary calls (defined, exists, etc.), not
# Chalk::IR::Node::Defined. Assertions match parser output, not eventual IR.
# ============================================================================

# --- L7/L8 tighter than L10 (arithmetic slurped into named-unary argument) ---
# perlop: + at L8, * at L7 — both TIGHTER than L10 named-unary.
# B::Concise: `defined $a + 1` → add[t2] then defined; Defined(Add($a, 1))
# B::Concise: `defined $a * 2` → multiply[t2] then defined; Defined(Multiply($a, 2))

subtest 'L8 + tighter than L10 named-unary: defined $a + 1 is Call(defined,[Add($a,1)])' => sub {
    # perlop: L8 (+) tighter than L10 (defined); "defined $a + 1" is
    # Defined(Add($a, 1)) per B::Concise. Named-unary slurps the arithmetic.
    my $expr = parse_expr('defined $a + 1');
    my $call = isa_with_shape($expr, 'Chalk::IR::Node::Call',
        'top is Call (defined)') or return;
    is($call->name(), 'defined', 'callee is defined');
    my $args = $call->inputs()->[1];
    ok(ref($args) eq 'ARRAY' && @$args, 'defined has args') or return;
    isa_with_shape($args->[0], 'Chalk::IR::Node::Add',
        'arg of defined is Add($a, 1)');
};

subtest 'L7 * tighter than L10 named-unary: defined $a * 2 is Call(defined,[Multiply($a,2)])' => sub {
    # perlop: L7 (*) tighter than L10 (defined); "defined $a * 2" is
    # Defined(Multiply($a, 2)) per B::Concise. Named-unary slurps the multiplication.
    my $expr = parse_expr('defined $a * 2');
    my $call = isa_with_shape($expr, 'Chalk::IR::Node::Call',
        'top is Call (defined)') or return;
    is($call->name(), 'defined', 'callee is defined');
    my $args = $call->inputs()->[1];
    ok(ref($args) eq 'ARRAY' && @$args, 'defined has args') or return;
    isa_with_shape($args->[0], 'Chalk::IR::Node::Multiply',
        'arg of defined is Multiply($a, 2)');
};

# --- L11 looser than L10 (isa does NOT get slurped into named-unary argument) ---
# perlop: isa at L11 — LOOSER than L10 named-unary.
# B::Concise: `defined $a isa Foo` → defined sK/1 then isa; IsaOp(Defined($a), Foo)

subtest 'L11 isa looser than L10 named-unary: defined $a isa Foo is IsaOp(Call(defined,$a),Foo)' => sub {
    # perlop: L11 (isa) looser than L10 (defined); "defined $a isa Foo" is
    # IsaOp(Defined($a), Foo) per B::Concise. Named-unary applies only to $a.
    my $expr = parse_expr('defined $a isa "Foo"');
    my $isa = isa_with_shape($expr, 'Chalk::IR::Node::IsaOp',
        'top is IsaOp') or return;
    my $call = isa_with_shape($isa->inputs()->[1], 'Chalk::IR::Node::Call',
        'left of IsaOp is Call (defined)') or return;
    is($call->name(), 'defined', 'callee is defined');
};

# --- L13 looser than L10 (comparison does NOT get slurped) ---
# perlop: == at L13, eq at L13 — LOOSER than L10 named-unary.
# B::Concise: `defined $a == 1` → defined sK/1 then eq vK/2; NumEq(Defined($a), 1)
# B::Concise: `defined $a eq "x"` → defined sK/1 then seq vK/2; StrEq(Defined($a), "x")

subtest 'L13 == looser than L10 named-unary: defined $a == 1 is NumEq(Call(defined,$a),1)' => sub {
    # perlop: L13 (==) looser than L10 (defined); "defined $a == 1" is
    # NumEq(Defined($a), 1) per B::Concise. Named-unary applies only to $a.
    my $expr = parse_expr('defined $a == 1');
    my $cmp = isa_with_shape($expr, 'Chalk::IR::Node::NumEq',
        'top is NumEq') or return;
    my $call = isa_with_shape($cmp->inputs()->[1], 'Chalk::IR::Node::Call',
        'left of NumEq is Call (defined)') or return;
    is($call->name(), 'defined', 'callee is defined');
};

subtest 'L13 eq looser than L10 named-unary: defined $a eq "x" is StrEq(Call(defined,$a),"x")' => sub {
    # perlop: L13 (eq) looser than L10 (defined); "defined $a eq \"x\"" is
    # StrEq(Defined($a), "x") per B::Concise. Named-unary applies only to $a.
    my $expr = parse_expr('defined $a eq "x"');
    my $cmp = isa_with_shape($expr, 'Chalk::IR::Node::StrEq',
        'top is StrEq') or return;
    my $call = isa_with_shape($cmp->inputs()->[1], 'Chalk::IR::Node::Call',
        'left of StrEq is Call (defined)') or return;
    is($call->name(), 'defined', 'callee is defined');
};

# --- L16/L17 looser than L10 (logical does NOT get slurped) ---
# perlop: && at L16, || at L17 — LOOSER than L10 named-unary.
# B::Concise: `defined $a && $b` → defined sK/1 then and; And(Defined($a), $b)
# B::Concise: `defined $a || 0` → defined sK/1 then or; Or(Defined($a), 0)

subtest 'L16 && looser than L10 named-unary: defined $a && $b is And(Call(defined,$a),$b)' => sub {
    # perlop: L16 (&&) looser than L10 (defined); "defined $a && $b" is
    # And(Defined($a), $b) per B::Concise. Named-unary applies only to $a.
    my $expr = parse_expr('defined $a && $b');
    my $and = isa_with_shape($expr, 'Chalk::IR::Node::And',
        'top is And') or return;
    my $call = isa_with_shape($and->inputs()->[1], 'Chalk::IR::Node::Call',
        'left of And is Call (defined)') or return;
    is($call->name(), 'defined', 'callee is defined');
};

subtest 'L17 || looser than L10 named-unary: defined $a || 0 is Or(Call(defined,$a),0)' => sub {
    # perlop: L17 (||) looser than L10 (defined); "defined $a || 0" is
    # Or(Defined($a), 0) per B::Concise. Named-unary applies only to $a.
    my $expr = parse_expr('defined $a || 0');
    my $or = isa_with_shape($expr, 'Chalk::IR::Node::Or',
        'top is Or') or return;
    my $call = isa_with_shape($or->inputs()->[1], 'Chalk::IR::Node::Call',
        'left of Or is Call (defined)') or return;
    is($call->name(), 'defined', 'callee is defined');
};

done_testing;
