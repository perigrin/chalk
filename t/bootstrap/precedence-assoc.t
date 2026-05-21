# ABOUTME: Tests AssignmentExpression and TernaryExpression associativity in Precedence semiring.
# ABOUTME: Covers Bug 3: two AssignmentExpressions in C-style for header rejected by [B,P,TI] combo.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Semiring::Precedence;
use Chalk::Bootstrap::Context;
use Scalar::Util qw(refaddr);

# ========================================================================
# Unit tests on _complete_prec via multiply() with complete-annotated
# Contexts. These verify the per-rule assoc shape without going through
# the full pipeline.
# ========================================================================

my $prec = Chalk::Bootstrap::Semiring::Precedence->new(
    lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
);

# Helper: build a complete-annotated Context for multiply() calls.
my $make_complete = sub ($value, $rule_name, $alt_idx = 0) {
    return Chalk::Bootstrap::Context->new(
        focus       => undef,
        children    => [$value],
        position    => 0,
        annotations => {
            complete  => true,
            rule_name => $rule_name,
            alt_idx   => $alt_idx,
            pos       => 0,
            origin    => 0,
        },
    );
};

# Test 1: _complete_prec for AssignmentExpression returns assoc='right'
# Before the fix, the EXPR_LEVELS clause returns assoc=undef (not 'right').
{
    my $result = $prec->multiply($prec->one(), $make_complete->($prec->one(), 'AssignmentExpression'));
    ok(!$prec->is_zero($result), '_complete_prec(AssignmentExpression) is not zero');
    is($result->{assoc}, 'right', 'AssignmentExpression completes with assoc=right');
}

# Test 2: _complete_prec for TernaryExpression returns assoc='right'
# Perl ?: is right-associative; the latent same-level-reject risk.
{
    my $result = $prec->multiply($prec->one(), $make_complete->($prec->one(), 'TernaryExpression'));
    ok(!$prec->is_zero($result), '_complete_prec(TernaryExpression) is not zero');
    is($result->{assoc}, 'right', 'TernaryExpression completes with assoc=right');
}

# Test 3: _complete_prec for PostfixExpression / UnaryExpression: assoc undef is fine (negative level).
# Negative levels never hit same-level reject, so assoc=undef is acceptable there.
{
    my $post_result = $prec->multiply($prec->one(), $make_complete->($prec->one(), 'PostfixExpression'));
    ok(!$prec->is_zero($post_result), '_complete_prec(PostfixExpression) is not zero');
    is($post_result->{level}, -2, 'PostfixExpression level is -2');

    my $unary_result = $prec->multiply($prec->one(), $make_complete->($prec->one(), 'UnaryExpression'));
    ok(!$prec->is_zero($unary_result), '_complete_prec(UnaryExpression) is not zero');
    is($unary_result->{level}, -1, 'UnaryExpression level is -1');
}

# Test 4: Synthetic chart-complete multiply — two AssignmentExpression values must NOT reject.
# This exercises the multiply path that caused Bug 3:
# L = (level=101 assoc=??? isop=F) meets R = (level=101 assoc=??? isop=F).
# Before fix: assoc=undef → default 'left' → same-level left-assoc → reject.
# After fix: assoc='right' → same-level right-assoc + non-operator right → pass through.
{
    my $assign_level_value = $prec->multiply($prec->one(), $make_complete->($prec->one(), 'AssignmentExpression'));
    ok(!$prec->is_zero($assign_level_value), 'assignment expression completion is not zero');

    # Now multiply L (carrying level=101) with another AssignmentExpression completion (level=101).
    # This is the chart-complete multiply that was rejecting.
    my $result = $prec->multiply($assign_level_value, $make_complete->($prec->one(), 'AssignmentExpression'));
    ok(!$prec->is_zero($result),
        'two AssignmentExpression completions at same level do not reject (right-assoc)');
}

# ========================================================================
# Full-pipeline integration tests using build_perl_ir_parser.
# These are the acceptance criteria inputs from the RCA.
# ========================================================================

my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::PrecAssocTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::PrecAssocTest::grammar();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'Concise parser not built', 1 unless defined $parser;

    my sub parse_ok($source) {
        my $result = $parser->parse_value($source);
        return undef unless defined $result;
        return undef if $result->is_zero();
        return $result;
    }

    # --- Bug 3 cases: must FAIL before fix, PASS after fix ---

    {
        my $result = parse_ok('sub f { my $x; for (my $i = 0; $i < $x; $i += 2) { last; } }');
        ok(defined $result, 'Bug 3 case: for (my $i=0; cond; $i+=2) parses (5-ary pipeline)');
    }

    {
        my @arr;
        my $result = parse_ok('sub f { my @arr; for (my $i = 0; $i < scalar(@arr); $i += 2) { last; } }');
        ok(defined $result, 'Bug 3 case: for (my $i=0; $i < scalar(@arr); $i+=2) parses');
    }

    {
        my $result = parse_ok('sub f { my $i; for ($i = 0; $i < 10; $i += 2) { last; } }');
        ok(defined $result, 'Bug 3 case: for ($i=0; cond; $i+=2) without my decl parses');
    }

    {
        my $result = parse_ok('sub f { my $i; for ($i = 0; ; $i = 1) { last; } }');
        ok(defined $result, 'Bug 3 case: for ($i=0;; $i=1) two assignments parses');
    }

    # --- TernaryExpression latent cases ---
    # Probe whether chained ternary (right-associative) works before and after fix.

    {
        my $result = parse_ok('sub f { my ($a, $b, $c, $d, $e); my $x = $a ? $b : $c ? $d : $e; }');
        ok(defined $result, 'TernaryExpression: chained ternary (right-assoc chain) parses');
    }

    {
        my $result = parse_ok('sub f { my ($a, $x); my $y = $a == 1 ? "one" : $a == 2 ? "two" : "other"; }');
        ok(defined $result, 'TernaryExpression: nested ternary (common idiom) parses');
    }

    # --- Regression guards: must PASS before AND after fix ---

    {
        my $result = parse_ok('sub f { my $x = 1 + 2; }');
        ok(defined $result, 'regression: basic arithmetic parses');
    }

    {
        my $result = parse_ok('sub f { my ($a, $b, $c); my $x = $a = $b = $c; }');
        ok(defined $result, 'regression: chained assignment (right-assoc) parses');
    }

    {
        my $result = parse_ok('sub f { for (my $i = 0; $i < 10; $i++) { last; } }');
        ok(defined $result, 'regression: simple for-loop with ++ parses');
    }

    {
        my $result = parse_ok('sub f { my ($a, $b, $c); my $x = $a ? $b : $c; }');
        ok(defined $result, 'regression: single ternary (right-assoc) parses');
    }

    {
        my $result = parse_ok('sub f { my @arr; my @x = $arr->@[0..2]; }');
        ok(defined $result, 'regression (Fix A): postfix array slice parses');
    }

    {
        my $result = parse_ok('sub f { my $arr; my $n = $#{$arr}; }');
        ok(defined $result, 'regression (Fix B): $#{$arr} last index parses');
    }

    {
        my $result = parse_ok('sub f { my @arr; my @r = map { defined $_ } @arr; }');
        ok(defined $result, 'regression (Bug 4): map with defined in block parses');
    }

    {
        my $result = parse_ok('sub f { my ($x, @arr); defined func($x, @arr); }');
        ok(defined $result, 'regression (Finding 7 A3): defined func($x, @arr) parses');
    }
}

done_testing();
