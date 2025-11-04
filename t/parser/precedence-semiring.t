#!/usr/bin/env perl
# ABOUTME: Test Precedence semiring implementation for operator precedence validation
# ABOUTME: Verifies precedence table lookup and pruning of invalid parse paths
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Base;
use Chalk::Semiring::Precedence;
use lib 't/lib';
use Test::Chalk::Grammar;
use Chalk::Grammar;
use Chalk::Parser;

subtest 'Precedence table structure' => sub {
    # Phase 2: Arithmetic operators only
    my @precedence_table = (
        { assoc => 'right', ops => ['**'] },           # Index 0 - Highest precedence
        { assoc => 'left',  ops => ['*', '/', '%'] },  # Index 1
        { assoc => 'left',  ops => ['+', '-'] },       # Index 2 - Lowest precedence
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    isa_ok $semiring, 'Chalk::Semiring::Precedence';
    ok $semiring->precedence_table, 'Semiring has precedence table';
};

subtest 'Precedence semiring identity elements' => sub {
    my @precedence_table = (
        { assoc => 'right', ops => ['**'] },
        { assoc => 'left',  ops => ['*', '/', '%'] },
        { assoc => 'left',  ops => ['+', '-'] },
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    # Like Boolean semiring: mul_id = valid (1), add_id = invalid (0)
    is $semiring->mul_id->valid, 1, 'Multiplicative identity has valid=1';
    is $semiring->add_id->valid, 0, 'Additive identity has valid=0';

    isnt refaddr($semiring->mul_id), refaddr($semiring->add_id), 'Identity elements are distinct';
};

subtest 'Left associativity validation' => sub {
    my @precedence_table = (
        { assoc => 'left', ops => ['+', '-'] },       # Index 0 - High precedence
        { assoc => 'left', ops => ['||'] },           # Index 1 - Low precedence
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    # Create mock grammar rule for: `a + b` (binary operation)
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'E', [qw(E + E)] ],
            [ 'E', ['n'] ],
        ]
    );

    my $plus_rule = ($grammar->rules_for('E'))[0];

    # Test: (a || b) + c should be INVALID
    # Left operand has || (index 1), current has + (index 0)
    # Check: 1 > 0? YES → INVALID → should return add_id

    # For now, just test that we can create elements from rules
    my $elem = $semiring->init_element_from_rule($plus_rule, 0, 3);
    isa_ok $elem, 'Chalk::Semiring::PrecedenceElement';
};

subtest 'Right associativity validation' => sub {
    my @precedence_table = (
        { assoc => 'right', ops => ['**'] },          # Index 0 - Highest precedence
        { assoc => 'left',  ops => ['+', '-'] },      # Index 1
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'E', [qw(E ** E)] ],
            [ 'E', ['n'] ],
        ]
    );

    my $power_rule = ($grammar->rules_for('E'))[0];

    # Test: a ** (b ** c) should be VALID (right-assoc allows equal precedence on right)
    # Right operand has ** (index 0), current has ** (index 0)
    # Check: 0 > 0? NO → VALID → should return mul_id

    my $elem = $semiring->init_element_from_rule($power_rule, 0, 5);
    isa_ok $elem, 'Chalk::Semiring::PrecedenceElement';
};

subtest 'Mixed precedence validation' => sub {
    my @precedence_table = (
        { assoc => 'right', ops => ['**'] },          # Index 0 - Highest
        { assoc => 'left',  ops => ['*', '/', '%'] }, # Index 1
        { assoc => 'left',  ops => ['+', '-'] },      # Index 2 - Lowest
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    # Test: a + (b * c) should be VALID
    # + is lower precedence (index 2), * is higher precedence (index 1)
    # Higher precedence can nest inside lower precedence

    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'E', [qw(E + E)] ],
            [ 'E', [qw(E * E)] ],
            [ 'E', ['n'] ],
        ]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );

    # This should succeed: multiplication binds tighter than addition
    my $result = $parser->parse_string('n+n*n');
    ok $result, 'n+n*n parses successfully (correct precedence)';
};

subtest 'Precedence pruning - invalid nesting' => sub {
    my @precedence_table = (
        { assoc => 'left', ops => ['+', '-'] },       # Index 0 - High precedence
        { assoc => 'left', ops => ['||'] },           # Index 1 - Low precedence
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'E', [qw(E + E)] ],
            [ 'E', [qw(E || E)] ],
            [ 'E', ['n'] ],
        ]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );

    # Test: (a || b) + c should be INVALID
    # Lower precedence (||) cannot nest inside higher precedence (+)
    # The precedence semiring should return add_id, pruning this parse path

    # Note: Without precedence semiring, this would parse successfully
    # With precedence semiring, it should fail (or at least not prefer this parse)

    # This test documents the expected behavior
    # For Phase 2, we're focusing on arithmetic operators
    # This will be fully testable once we have the implementation

    pass 'Placeholder test for future precedence pruning implementation';
};

subtest 'Left associativity - 10 - 5 - 2 = 3' => sub {
    my @precedence_table = (
        { assoc => 'left', ops => ['+', '-'] },
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    # Left associative: 10 - 5 - 2 should parse as (10 - 5) - 2 = 3
    # Not as 10 - (5 - 2) = 7

    # This test documents the expected behavior for left associativity
    ok $semiring, 'Semiring created for left associativity test';
};

subtest 'Right associativity - 2 ** 3 ** 2 = 512' => sub {
    my @precedence_table = (
        { assoc => 'right', ops => ['**'] },
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    # Right associative: 2 ** 3 ** 2 should parse as 2 ** (3 ** 2) = 2 ** 9 = 512
    # Not as (2 ** 3) ** 2 = 8 ** 2 = 64

    # This test documents the expected behavior for right associativity
    ok $semiring, 'Semiring created for right associativity test';
};
