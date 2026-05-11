# ABOUTME: Conformance test for L3 (++ --) and L6 (=~ !~) per perlop.pod (Perl 5.42).
# ABOUTME: Each subtest cites the perlop level pair and asserts IR shape; TODO = current gap.
#
# This file is a TDD spec: every subtest is derived from perlop.pod's
# documented precedence table for the high-precedence non-arrow operators.
# Tests that fail on current Chalk are marked TODO.
#
# perlop.pod relevant levels (highest to lowest):
#
#     L1   left      terms and list operators (leftward)
#     L2   left      ->
#     L3   nonassoc  ++ --                  <-- this file
#     L4   right     **
#     L5   right     ! ~ ~. \ and unary + and -
#     L6   left      =~ !~                  <-- this file
#     L7   left      * / % x
#
# Lower number = tighter binding.
#
# Verbatim from perlop.pod (Auto-increment and Auto-decrement):
#   "++" and "--" work as in C.  That is, if placed before a variable,
#   they increment or decrement the variable by one before returning the
#   value, and if placed after, increment or decrement after returning the
#   value.
#
# Verbatim from perlop.pod (Binding Operators):
#   Binary "=~" binds a scalar expression to a pattern match.
#   Binary "!~" is just like "=~" except the return value is negated in
#   the logical sense.

use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use PrecedenceSpecHelpers qw(parse_expr shape_of isa_with_shape);

use Chalk::IR::Node;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::CompoundAssign;
use Chalk::IR::Node::Power;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Subscript;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::PostfixDeref;
use Chalk::IR::Node::Not;
use Chalk::IR::Node::RegexMatch;
use Chalk::IR::Node::NotMatch;
use Chalk::IR::Node::RegexSubst;

# ============================================================================
# L3 nonassoc baseline: ++ and -- as suffix
# ----------------------------------------------------------------------------
# perlop: "if placed after, increment or decrement after returning the value."
# Chalk currently desugars $x++ to CompoundAssign(+=, $x, 1) and $x-- to
# CompoundAssign(-=, $x, 1) — which is observationally equivalent for the
# value-returning side but loses the pre/post distinction. The test asserts
# the desugaring shape that Chalk actually produces.
# ============================================================================

subtest 'L3 post-increment $x++ desugars to CompoundAssign(+=, $x, 1)' => sub {
    my $expr = parse_expr('$x++');
    my $ca = isa_with_shape($expr, 'Chalk::IR::Node::CompoundAssign',
        'top is CompoundAssign') or return;
    # CompoundAssign exposes its op as a Constant via ->op or as inputs->[0].
    is($ca->inputs()->[0]->value(), '+=', 'op is +=');
    is($ca->inputs()->[1]->value(), '$x', 'lhs is $x');
    is($ca->inputs()->[2]->value(), '1', 'rhs is 1');
};

subtest 'L3 post-decrement $x-- desugars to CompoundAssign(-=, $x, 1)' => sub {
    my $expr = parse_expr('$x--');
    my $ca = isa_with_shape($expr, 'Chalk::IR::Node::CompoundAssign',
        'top is CompoundAssign') or return;
    is($ca->inputs()->[0]->value(), '-=', 'op is -=');
    is($ca->inputs()->[1]->value(), '$x', 'lhs is $x');
    is($ca->inputs()->[2]->value(), '1', 'rhs is 1');
};

# ============================================================================
# Pre vs post: structural distinction must exist
# ----------------------------------------------------------------------------
# perlop: pre-increment "increment ... before returning the value", post-
# increment "increment ... after returning the value." These are semantically
# distinct and must produce structurally different IR. Chalk currently
# silently drops the prefix ++ / -- (returns just the operand), losing the
# distinction entirely.
# ============================================================================

subtest 'L3 pre-increment ++$x is structurally distinct from post $x++' => sub {
    my $pre  = parse_expr('++$x');
    my $post = parse_expr('$x++');

    TODO: {
        local $TODO = 'Pre-increment ++$x silently drops the operator '
                    . '(parse returns bare $x), losing pre/post distinction';
        ok(defined $pre, 'pre-increment parses');
        ok(defined $post, 'post-increment parses');
        if (defined $pre && defined $post) {
            isnt(shape_of($pre), shape_of($post),
                'pre and post produce different IR shapes');
        }
    }
};

# ============================================================================
# L3 nonassoc: chaining $x++ ++ should be a syntax error per perlop
# ----------------------------------------------------------------------------
# perlop classifies L3 as "nonassoc". Chaining (e.g. $x++ ++) is not a valid
# Perl program; the reference perl interpreter rejects it. Chalk currently
# accepts $x++ ++ and produces nested CompoundAssign — a precedence-table gap.
# ============================================================================

subtest 'L3 nonassoc: $x++ ++ should be a syntax error' => sub {
    my $expr = parse_expr('$x++ ++');

    TODO: {
        local $TODO = 'L3 nonassoc not enforced; Chalk accepts $x++ ++ '
                    . 'and produces nested CompoundAssign';
        ok(!defined $expr, 'parse should fail (nonassoc violation)')
            or diag('  got shape: ' . shape_of($expr));
    }
};

# ============================================================================
# L3 (++) tighter than L4 (**): $x ** $y++ is $x ** ($y++)
# ----------------------------------------------------------------------------
# perlop: ++ at L3, ** at L4 — increment binds tighter than exponentiation.
# Expected: Power($x, CompoundAssign(+=, $y, 1)).
# ============================================================================

subtest 'L3 ++ tighter than L4 **: $x ** $y++ is Power($x, ($y++))' => sub {
    my $expr = parse_expr('$x ** $y++');
    my $pow = isa_with_shape($expr, 'Chalk::IR::Node::Power',
        'top is Power') or return;
    # Power input shape per probe: [op_constant, lhs, rhs]
    is($pow->inputs()->[1]->value(), '$x', 'left of Power is $x');
    my $ca = isa_with_shape($pow->inputs()->[2], 'Chalk::IR::Node::CompoundAssign',
        'right of Power is CompoundAssign (the ++)') or return;
    is($ca->inputs()->[0]->value(), '+=', 'inner op is +=');
    is($ca->inputs()->[1]->value(), '$y', 'inner lhs is $y');
};

# ============================================================================
# L3 (++) with L2 (->) method call: $obj->method()++
# ----------------------------------------------------------------------------
# perlop: -> at L2, ++ at L3 — method call (L2) binds tighter than ++ (L3),
# so the increment wraps the entire call. Expected:
#   CompoundAssign(+=, Call($obj, method, []), 1)
# Note: $obj->method()++ is not a meaningful program (you can't increment
# the rvalue from a method call), but it's a useful precedence probe.
# ============================================================================

subtest 'L3 ++ outside L2 ->: $obj->method()++ is ($obj->method())++' => sub {
    my $expr = parse_expr('$obj->method()++');
    my $ca = isa_with_shape($expr, 'Chalk::IR::Node::CompoundAssign',
        'top is CompoundAssign') or return;
    is($ca->inputs()->[0]->value(), '+=', 'op is +=');
    isa_with_shape($ca->inputs()->[1], 'Chalk::IR::Node::Call',
        'lhs is Call (method invocation)');
    is($ca->inputs()->[2]->value(), '1', 'rhs is 1');
};

# ============================================================================
# L3 (++) with L2 (subscript): $h{key}++
# ----------------------------------------------------------------------------
# perlop: subscript at L2, ++ at L3 — subscript binds tighter so the post-
# increment wraps the indexed location. Expected:
#   CompoundAssign(+=, Subscript($h, key, hash), 1)
# ============================================================================

subtest 'L3 ++ outside L2 subscript: $h{key}++ is ($h{key})++' => sub {
    my $expr = parse_expr('$h{key}++');
    my $ca = isa_with_shape($expr, 'Chalk::IR::Node::CompoundAssign',
        'top is CompoundAssign') or return;
    is($ca->inputs()->[0]->value(), '+=', 'op is +=');
    isa_with_shape($ca->inputs()->[1], 'Chalk::IR::Node::Subscript',
        'lhs is Subscript ($h{key})');
    is($ca->inputs()->[2]->value(), '1', 'rhs is 1');
};

# ============================================================================
# L3 (++) with bareword method dispatch: $obj->prop++
# ----------------------------------------------------------------------------
# perlop: -> at L2, ++ at L3. Without parens, $obj->prop is treated as a
# method call; ++ then wraps it. Expected:
#   CompoundAssign(+=, Call($obj, prop, []), 1)
# ============================================================================

subtest 'L3 ++ outside L2 method-no-parens: $obj->prop++ wraps Call' => sub {
    my $expr = parse_expr('$obj->prop++');
    my $ca = isa_with_shape($expr, 'Chalk::IR::Node::CompoundAssign',
        'top is CompoundAssign') or return;
    is($ca->inputs()->[0]->value(), '+=', 'op is +=');
    my $call = isa_with_shape($ca->inputs()->[1], 'Chalk::IR::Node::Call',
        'lhs is Call ($obj->prop)') or return;
    # Call input shape: [invocant, method_name_constant, args_arrayref]
    is($call->inputs()->[1]->value(), 'prop', 'method name is prop');
};

# ============================================================================
# L6 (=~) baseline: $x =~ /pat/
# ----------------------------------------------------------------------------
# perlop: Binary "=~" binds a scalar expression to a pattern match. Chalk
# represents this as a RegexMatch node (subclass of Regex, not BinOp).
# ============================================================================

subtest 'L6 =~ baseline: $x =~ /pat/ produces RegexMatch' => sub {
    my $expr = parse_expr('$x =~ /pat/');
    my $rm = isa_with_shape($expr, 'Chalk::IR::Node::RegexMatch',
        'top is RegexMatch') or return;
    # Inputs per probe: [lhs, /pattern/, flags]
    is($rm->inputs()->[0]->value(), '$x', 'lhs is $x');
};

# ============================================================================
# L6 (!~) baseline: $x !~ /pat/ — different node type from =~
# ----------------------------------------------------------------------------
# perlop: Binary "!~" is just like "=~" except the return value is negated.
# Same precedence (L6) but distinct node class (NotMatch is a BinOp,
# RegexMatch is a Regex). The two operators must produce different IR types.
# ============================================================================

subtest 'L6 !~ produces NotMatch (distinct from RegexMatch)' => sub {
    my $expr = parse_expr('$x !~ /pat/');
    my $nm = isa_with_shape($expr, 'Chalk::IR::Node::NotMatch',
        'top is NotMatch') or return;
    isnt(ref($nm), 'Chalk::IR::Node::RegexMatch',
        '!~ does not produce RegexMatch');
    is($nm->op_str(), '!~', 'op_str is !~');
};

# ============================================================================
# L5 (!) tighter than L6 (=~): ! $x =~ /pat/ is (! $x) =~ /pat/
# ----------------------------------------------------------------------------
# perlop: ! at L5, =~ at L6 — unary ! binds tighter than =~, so the
# negation wraps just $x and the result is the LHS of the binding.
# Expected: RegexMatch(Not($x), /pat/, '').
# ============================================================================

subtest 'L5 ! tighter than L6 =~: ! $x =~ /pat/ is RegexMatch(Not($x), /pat/)' => sub {
    my $expr = parse_expr('! $x =~ /pat/');
    my $rm = isa_with_shape($expr, 'Chalk::IR::Node::RegexMatch',
        'top is RegexMatch') or return;
    isa_with_shape($rm->inputs()->[0], 'Chalk::IR::Node::Not',
        'lhs is Not (the ! consumed $x first)');
};

# ============================================================================
# L6 (=~) tighter than L7 (*): $x =~ /pat/ * 2 is (=~) * 2
# ----------------------------------------------------------------------------
# perlop: =~ at L6, * at L7 — binding tighter than multiplication, so
# the match result is the LHS of the multiplication.
# Expected: Multiply(RegexMatch($x, /pat/, ''), 2).
# ============================================================================

subtest 'L6 =~ tighter than L7 *: $x =~ /pat/ * 2 is Multiply(RegexMatch, 2)' => sub {
    my $expr = parse_expr('$x =~ /pat/ * 2');
    my $mul = isa_with_shape($expr, 'Chalk::IR::Node::Multiply',
        'top is Multiply') or return;
    # Multiply inputs per probe: [op_constant, lhs, rhs]
    isa_with_shape($mul->inputs()->[1], 'Chalk::IR::Node::RegexMatch',
        'left of Multiply is RegexMatch');
    is($mul->inputs()->[2]->value(), '2', 'right of Multiply is 2');
};

# ============================================================================
# L6 left-associativity: $x =~ /a/ =~ /b/ groups left
# ----------------------------------------------------------------------------
# perlop: L6 is "left" associative. Chaining bindings groups left-to-right:
# the result of the first match (a true/false-ish scalar) is bound by the
# second. Expected: RegexMatch(RegexMatch($x, /a/, ''), /b/, '').
# ============================================================================

subtest 'L6 left-assoc: $x =~ /a/ =~ /b/ is RegexMatch(RegexMatch, /b/)' => sub {
    my $expr = parse_expr('$x =~ /a/ =~ /b/');
    my $outer = isa_with_shape($expr, 'Chalk::IR::Node::RegexMatch',
        'outer is RegexMatch') or return;
    isa_with_shape($outer->inputs()->[0], 'Chalk::IR::Node::RegexMatch',
        'inner (lhs) is also RegexMatch (left-assoc)');
};

# ============================================================================
# L6 substitution: $x =~ s/a/b/ produces RegexSubst
# ----------------------------------------------------------------------------
# perlop: "The right argument is a search pattern, substitution, or
# transliteration." Substitution at the same L6 binding level produces a
# distinct node type (RegexSubst, not RegexMatch).
# ============================================================================

subtest 'L6 =~ with s///: $x =~ s/a/b/ produces RegexSubst' => sub {
    my $expr = parse_expr('$x =~ s/a/b/');
    my $rs = isa_with_shape($expr, 'Chalk::IR::Node::RegexSubst',
        'top is RegexSubst') or return;
    is($rs->inputs()->[0]->value(), '$x', 'lhs is $x');
    isnt(ref($rs), 'Chalk::IR::Node::RegexMatch',
        'substitution does not collapse to RegexMatch');
};

# ============================================================================
# L6 transliteration: $x =~ tr/a/b/ — currently unsupported in grammar
# ----------------------------------------------------------------------------
# perlop: tr/// (and y///) are L6 binding-targets like m// and s///.
# Chalk's grammar does not yet recognize tr///; the parse fails. Marked TODO
# until tr/// is added to the regex literal alternatives.
# ============================================================================

subtest 'L6 =~ with tr///: $x =~ tr/a/b/ should parse' => sub {
    my $expr = parse_expr('$x =~ tr/a/b/');

    ok(defined $expr, 'tr/// parses') or diag('  parse failed');
};

done_testing;
