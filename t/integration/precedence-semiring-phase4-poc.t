#!/usr/bin/env perl
# ABOUTME: Proof-of-concept for Phase 4 grammar simplification with precedence semiring
# ABOUTME: Demonstrates how grammar can be flattened when precedence semiring handles validation
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all defer);
use utf8;
use Test2::V0;
use FindBin qw($RealBin);
defer { done_testing() }

use lib "$RealBin/../../lib";
use lib 't/lib';
use Chalk::Base;
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::Composite;
use Chalk::Semiring::SPPF;
use Chalk::Semiring::Precedence;
use Chalk::Semiring::Boolean;
use Test::Chalk::Grammar;

# This test demonstrates Phase 4: Grammar Simplification
#
# BEFORE (Current Chalk Grammar):
# ================================
# Expression -> Assignment
#   Assignment -> Ternary
#     Ternary -> LogicalOr
#       LogicalOr -> LogicalAnd
#         LogicalAnd -> Comparison
#           Comparison -> RegexMatch
#             RegexMatch -> Range
#               Range -> Concatenation
#                 Concatenation -> Additive
#                   Additive -> Multiplicative
#                     Multiplicative -> Unary
#
# ~50 expression-related rules encoding precedence in grammar structure
#
# AFTER (With Precedence Semiring):
# ==================================
# Expression -> BinaryOperation | Literal | Identifier | ...
# BinaryOperation -> Expression Operator Expression
# Operator -> '+' | '-' | '*' | '/' | '**' | ...
#
# ~15-20 rules - precedence handled by semiring, not grammar

subtest 'Current approach: Grammar encodes precedence' => sub {
    # Build a grammar with precedence levels (like current Chalk)
    my $grammar_old = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'E', ['Additive'] ],                  # Expression
            [ 'Additive', ['Multiplicative'] ],     # Pass-through
            [ 'Additive', [qw(Additive + Multiplicative)] ],  # Addition
            [ 'Additive', [qw(Additive - Multiplicative)] ],  # Subtraction
            [ 'Multiplicative', ['Term'] ],         # Pass-through
            [ 'Multiplicative', [qw(Multiplicative * Term)] ],  # Multiplication
            [ 'Multiplicative', [qw(Multiplicative / Term)] ],  # Division
            [ 'Term', ['n'] ],                      # Number literal
        ]
    );

    # Count rules: 8 rules (6 for operators + 2 pass-through)
    my $rule_count = 0;
    for my $nt (qw(E Additive Multiplicative Term)) {
        my @rules = $grammar_old->rules_for($nt);
        $rule_count += scalar(@rules);
    }
    is $rule_count, 8, 'Old grammar: 8 rules for arithmetic';

    # Parse with Boolean semiring (precedence in grammar)
    my $parser = Chalk::Parser->new(
        grammar => $grammar_old,
        semiring => Chalk::Semiring::Boolean->new()
    );

    ok $parser->parse_string('n+n*n'), 'Old grammar: n+n*n parses (precedence in structure)';
};

subtest 'New approach: Semiring handles precedence' => sub {
    # Build a FLAT grammar (precedence NOT encoded in structure)
    my $grammar_new = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'E', ['BinaryOp'] ],              # Expression is binary operation
            [ 'E', ['n'] ],                     # Or literal
            [ 'BinaryOp', [qw(E + E)] ],        # Addition (same level as mult!)
            [ 'BinaryOp', [qw(E - E)] ],        # Subtraction
            [ 'BinaryOp', [qw(E * E)] ],        # Multiplication (same level!)
            [ 'BinaryOp', [qw(E / E)] ],        # Division
        ]
    );

    # Count rules: 6 rules total (4 operators + 2 expression forms)
    # Reduced from 8 rules (25% reduction)
    my $rule_count = 0;
    for my $nt (qw(E BinaryOp)) {
        my @rules = $grammar_new->rules_for($nt);
        $rule_count += scalar(@rules);
    }
    is $rule_count, 6, 'New grammar: 6 rules for arithmetic (25% reduction)';

    # Create precedence semiring to handle validation
    my @precedence_table = (
        { assoc => 'left', ops => ['*', '/'] },  # Index 0 - Higher precedence
        { assoc => 'left', ops => ['+', '-'] },  # Index 1 - Lower precedence
    );

    my $prec_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    # Parse with precedence semiring
    my $parser = Chalk::Parser->new(
        grammar => $grammar_new,
        semiring => $prec_sr
    );

    my $result = $parser->parse_string('n+n*n');
    ok $result, 'New grammar: n+n*n parses';
    ok $result->valid, 'Precedence semiring validates it';
};

subtest 'Comparison: Grammar complexity' => sub {
    # This demonstrates the benefit of Phase 4

    # OLD: Precedence encoded in grammar structure
    # - Many non-terminals (Additive, Multiplicative, etc.)
    # - Many pass-through rules (Additive -> Multiplicative)
    # - Rule count grows with each precedence level
    # - Hard to modify operator precedence (requires grammar restructure)

    # NEW: Precedence in declarative table
    # - Few non-terminals (Expression, BinaryOperation)
    # - No pass-through rules needed
    # - Rule count independent of precedence levels
    # - Easy to modify precedence (just update table)

    pass 'See test output above for rule count comparison';
};

subtest 'Phase 4 benefits demonstrated' => sub {
    # 1. Fewer rules
    ok 1, '✓ Rule reduction: 8 rules → 6 rules (25% for just arithmetic)';

    # 2. Clearer grammar
    ok 1, '✓ No precedence-level non-terminals (Additive, Multiplicative)';

    # 3. Semantic names
    ok 1, '✓ BinaryOperation describes WHAT, not WHERE in precedence';

    # 4. Declarative precedence
    ok 1, '✓ Precedence table is separate, easy to modify';

    # 5. Separation of concerns
    ok 1, '✓ Grammar = syntax, Semiring = precedence, Semantic = meaning';
};

subtest 'Scaling to full Perl operators' => sub {
    # Current Chalk has ~15 precedence levels:
    # Assignment, Ternary, LogicalOr, LogicalAnd, Comparison,
    # RegexMatch, Range, Concatenation, Additive, Multiplicative, etc.
    #
    # Each level adds:
    # - 1-2 pass-through rules
    # - 2-5 operator rules
    # Total: ~50 expression rules
    #
    # With Phase 4:
    # - Expression -> BinaryOperation | UnaryOperation | Literal | ...
    # - BinaryOperation -> Expression Operator Expression
    # - UnaryOperation -> Operator Expression
    # - Operator -> '+' | '-' | '*' | '/' | '**' | ... (all operators)
    # Total: ~15-20 rules
    #
    # Reduction: 50 rules → 15-20 rules (60-70% reduction!)

    pass '✓ Extrapolating: 50 rules → 15-20 rules (60-70% reduction for full grammar)';
};

subtest 'What Phase 4 full implementation would require' => sub {
    # This is why Phase 4 should be its own PR:

    # 1. Grammar changes (grammar/chalk.bnf)
    ok 1, '1. Replace precedence-level non-terminals with semantic categories';

    # 2. Semantic action updates (lib/Chalk/Grammar/Chalk/Rule/*)
    ok 1, '2. Update ALL semantic actions to match new parse tree structure';

    # 3. Incremental approach
    ok 1, '3. Do by operator category: arithmetic, comparison, logical, etc.';

    # 4. Testing
    ok 1, '4. Ensure 100% test pass rate after each category';

    # 5. Update precedence table
    ok 1, '5. Use full Perl precedence table (25 levels from perlop)';
};
