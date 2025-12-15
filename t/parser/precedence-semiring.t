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

    # init_element_from_rule creates a plain valid element without operator info
    # Operators are extracted during on_scan when the actual token is scanned
    my $elem = $semiring->init_element_from_rule($plus_rule, 0, 5);

    # The element starts valid but doesn't have operator info yet
    # (operators are set during on_scan, not init_element_from_rule)
    is $elem->operator, undef, 'init_element_from_rule does not extract operator (done in on_scan)';
    is $elem->precedence_level, undef, 'Precedence level set during on_scan';
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
    # is_active => 1 means "current rule's operator" (parent)
    # is_active => 0 means "from sub-expression" (child)
    my $plus_active = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '+',
        precedence_level => 0,
        is_active => 1  # + is the current rule's operator
    );

    my $or_passive = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '||',
        precedence_level => 1,
        is_active => 0  # || is from a completed sub-expression
    );

    my $plus_passive = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '+',
        precedence_level => 0,
        is_active => 0  # + is from a completed sub-expression
    );

    my $or_active = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '||',
        precedence_level => 1,
        is_active => 1  # || is the current rule's operator
    );

    # VALID: Higher precedence (+) can be nested inside lower precedence (||)
    # Pattern: (a + b) || c - || is active (parent), + is passive (child)
    my $result1 = $or_active->multiply($plus_passive);
    is $result1->valid, 1, 'Higher precedence inside lower is valid';

    # INVALID: Lower precedence (||) cannot be nested inside higher precedence (+)
    # Pattern: (a || b) + c - + is active (parent), || is passive (child)
    my $result2 = $plus_active->multiply($or_passive);
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

    # Create elements with active/passive status
    my $power_active = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '**',
        precedence_level => 0,
        is_active => 1  # ** is current rule's operator
    );

    my $plus_passive = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '+',
        precedence_level => 1,
        is_active => 0  # + is from sub-expression
    );

    my $power_passive = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '**',
        precedence_level => 0,
        is_active => 0  # ** from sub-expression
    );

    my $plus_active = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '+',
        precedence_level => 1,
        is_active => 1  # + is current rule's operator
    );

    # VALID: Higher precedence (**) inside lower precedence (+)
    # Pattern: (a ** b) + c - + is active (parent), ** is passive (child)
    my $result1 = $plus_active->multiply($power_passive);
    is $result1->valid, 1, 'Higher precedence inside lower is valid';

    # INVALID: Lower precedence (+) inside higher precedence (**)
    # Pattern: (a + b) ** c - ** is active (parent), + is passive (child)
    my $result2 = $power_active->multiply($plus_passive);
    is $result2->valid, 0, 'Lower precedence inside higher is invalid';

    # VALID: Same precedence for right-associative operator
    # Pattern: a ** (b ** c) - right associativity allows this
    # Note: This test currently just checks basic precedence, not associativity rules
    my $result3 = $power_active->multiply($power_passive);
    is $result3->valid, 1, 'Same precedence is valid (basic check)';
};

subtest 'Phase 5: nonassoc operators cannot chain' => sub {
    my @precedence_table = (
        { assoc => 'nonassoc', ops => ['++', '--'] },  # Index 0 - Non-associative
        { assoc => 'left',     ops => ['+'] },          # Index 1
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    # Create elements
    my $incr_elem = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '++',
        precedence_level => 0,
        associativity => 'nonassoc'
    );

    my $plus_elem = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '+',
        precedence_level => 1,
        associativity => 'left'
    );

    # INVALID: Cannot chain nonassoc operators
    # Pattern: (a++) ++ - should be rejected
    my $result1 = $incr_elem->multiply($incr_elem);
    is $result1->valid, 0, 'nonassoc operators cannot chain with themselves';

    # VALID: nonassoc can combine with different operators
    # Pattern: (a++) + b
    my $result2 = $plus_elem->multiply($incr_elem);
    is $result2->valid, 1, 'nonassoc can combine with different operators';
};

subtest 'Phase 5: chained comparisons with directional validation' => sub {
    my @precedence_table = (
        { assoc => 'chained', ops => ['<', '<=', '>', '>='] },  # Index 0 - Chained comparisons
        { assoc => 'left',    ops => ['+'] },                    # Index 1
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    # Create elements for ascending operators
    my $lt_elem = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '<',
        precedence_level => 0,
        associativity => 'chained'
    );

    my $le_elem = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '<=',
        precedence_level => 0,
        associativity => 'chained'
    );

    # Create elements for descending operators
    my $gt_elem = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '>',
        precedence_level => 0,
        associativity => 'chained'
    );

    my $ge_elem = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '>=',
        precedence_level => 0,
        associativity => 'chained'
    );

    # VALID: Chaining ascending operators
    # Pattern: a < (b < c) - same direction
    my $result1 = $lt_elem->multiply($lt_elem);
    is $result1->valid, 1, 'chained: ascending < ascending is valid';

    # VALID: Chaining mixed ascending operators
    # Pattern: a < (b <= c) - both ascending
    my $result2 = $lt_elem->multiply($le_elem);
    is $result2->valid, 1, 'chained: ascending < ascending<= is valid';

    # VALID: Chaining descending operators
    # Pattern: a > (b > c) - same direction
    my $result3 = $gt_elem->multiply($gt_elem);
    is $result3->valid, 1, 'chained: descending > descending is valid';

    # INVALID: Mixing ascending and descending
    # Pattern: a < (b > c) - direction violation
    my $result4 = $lt_elem->multiply($gt_elem);
    is $result4->valid, 0, 'chained: ascending < descending is invalid (direction violation)';

    # INVALID: Mixing descending and ascending
    # Pattern: a > (b < c) - direction violation
    my $result5 = $gt_elem->multiply($lt_elem);
    is $result5->valid, 0, 'chained: descending > ascending is invalid (direction violation)';
};

subtest 'Phase 5: chain/na equality operators' => sub {
    my @precedence_table = (
        { assoc => 'chain/na', ops => ['==', '!=', 'eq', 'ne'] },  # Index 0 - Chain or nonassoc
        { assoc => 'left',     ops => ['+'] },                      # Index 1
    );

    my $semiring = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table
    );

    # Create elements
    my $eq_elem = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '==',
        precedence_level => 0,
        associativity => 'chain/na'
    );

    my $ne_elem = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '!=',
        precedence_level => 0,
        associativity => 'chain/na'
    );

    # VALID: Equality operators can chain in boolean context
    # Pattern: a == (b == c) - chained equality
    my $result1 = $eq_elem->multiply($eq_elem);
    is $result1->valid, 1, 'chain/na: equality operators can chain';

    # VALID: Can mix equality/inequality
    # Pattern: a == (b != c)
    my $result2 = $eq_elem->multiply($ne_elem);
    is $result2->valid, 1, 'chain/na: can mix == and !=';
};
