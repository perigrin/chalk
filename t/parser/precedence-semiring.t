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

subtest 'Extract operator from binary operation rule' => sub {
    my @precedence_table = (
        { assoc => 'left', ops => ['+', '-'] },
        { assoc => 'left', ops => ['*', '/'] },
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    # Create a grammar rule for: E -> E + E
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'E', [qw(E + E)] ],
            [ 'E', ['n'] ],
        ]
    );

    my $plus_rule = ($grammar->rules_for('E'))[0];

    # When we create an element from a binary operation rule,
    # it should extract and store the operator
    my $elem = $semiring->init_element_from_rule($plus_rule, 0, 5);

    # The element should identify this as a + operator
    is $elem->operator, '+', 'Extracts + operator from rule';
    is $elem->precedence_level, 0, 'Looks up precedence level for +';
    is $elem->valid, 1, 'Element starts as valid';
};

subtest 'Multiply validates precedence - left associativity' => sub {
    my @precedence_table = (
        { assoc => 'left', ops => ['+', '-'] },       # Index 0 - High precedence
        { assoc => 'left', ops => ['||'] },           # Index 1 - Low precedence
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    # Create elements representing operators
    my $plus_elem = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '+',
        precedence_level => 0
    );

    my $or_elem = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '||',
        precedence_level => 1
    );

    # VALID: Higher precedence (+) can be nested inside lower precedence (||)
    # Pattern: (a + b) || c
    my $result1 = $or_elem->multiply($plus_elem);
    is $result1->valid, 1, 'Higher precedence inside lower is valid';

    # INVALID: Lower precedence (||) cannot be nested inside higher precedence (+)
    # Pattern: (a || b) + c
    my $result2 = $plus_elem->multiply($or_elem);
    is $result2->valid, 0, 'Lower precedence inside higher is invalid';
};

subtest 'Multiply validates precedence - right associativity' => sub {
    my @precedence_table = (
        { assoc => 'right', ops => ['**'] },          # Index 0 - Highest
        { assoc => 'left',  ops => ['+'] },           # Index 1 - Lower
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    # Create elements
    my $power_elem = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '**',
        precedence_level => 0
    );

    my $plus_elem = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '+',
        precedence_level => 1
    );

    # VALID: Higher precedence (**) inside lower precedence (+)
    # Pattern: (a ** b) + c
    my $result1 = $plus_elem->multiply($power_elem);
    is $result1->valid, 1, 'Higher precedence inside lower is valid';

    # INVALID: Lower precedence (+) inside higher precedence (**)
    # Pattern: (a + b) ** c
    my $result2 = $power_elem->multiply($plus_elem);
    is $result2->valid, 0, 'Lower precedence inside higher is invalid';

    # VALID: Same precedence for right-associative operator
    # Pattern: a ** (b ** c) - right associativity allows this
    # Note: This test currently just checks basic precedence, not associativity rules
    my $result3 = $power_elem->multiply($power_elem);
    is $result3->valid, 1, 'Same precedence is valid (basic check)';
};
