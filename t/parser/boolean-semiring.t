#!/usr/bin/env perl
# ABOUTME: Test Boolean semiring implementation for fast validation mode
# ABOUTME: Verifies Boolean algebra operations and parser integration
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Base;
use Chalk::Semiring::Boolean;
use Test::Chalk::Grammar;
use Chalk::Grammar;
use Chalk::Parser;

subtest 'Boolean semiring algebra' => sub {
    my $semiring = Chalk::Semiring::Boolean->new();

    # Test identity elements
    is $semiring->mul_id->value, 1, 'Multiplicative identity is 1 (true)';
    is $semiring->add_id->value, 0, 'Additive identity is 0 (false)';

    # Create Boolean elements for testing
    my $false = Chalk::Semiring::BooleanElement->new(value => 0);
    my $true = Chalk::Semiring::BooleanElement->new(value => 1);

    # Test plus operation (OR/choice)
    is $semiring->plus($false, $false)->value, 0, '0 + 0 = 0 (false OR false = false)';
    is $semiring->plus($true, $false)->value, 1, '1 + 0 = 1 (true OR false = true)';
    is $semiring->plus($false, $true)->value, 1, '0 + 1 = 1 (false OR true = true)';
    is $semiring->plus($true, $true)->value, 1, '1 + 1 = 1 (true OR true = true)';

    # Test multiply operation (AND/sequence)
    is $semiring->multiply($false, $false)->value, 0, '0 * 0 = 0 (false AND false = false)';
    is $semiring->multiply($true, $false)->value, 0, '1 * 0 = 0 (true AND false = false)';
    is $semiring->multiply($false, $true)->value, 0, '0 * 1 = 0 (false AND true = false)';
    is $semiring->multiply($true, $true)->value, 1, '1 * 1 = 1 (true AND true = true)';
};

subtest 'Boolean semiring with simple grammar' => sub {
    my $grammar = Test::Chalk::Grammar->build_grammar(
        [],
        [ 'S' => [qw(A B)] ],
        [ 'A' => ['a'] ],
        [ 'B' => ['b'] ],
    );

    my $semiring = Chalk::Semiring::Boolean->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );

    my $result = $parser->parse_string('ab');
    ok $result, 'Valid parse returns truthy result';
    is $result->value, 1, 'Result value is 1 (true)';

    my $fail_result = $parser->parse_string('ax');
    is $fail_result, undef, 'Invalid parse returns undef';
};

subtest 'Boolean semiring with ambiguous grammar' => sub {
    my $grammar = Test::Chalk::Grammar->build_grammar(
        [],
        [ 'E' => [qw(E + E)] ],
        [ 'E' => [qw(E * E)] ],
        [ 'E' => ['n'] ],
    );

    my $semiring = Chalk::Semiring::Boolean->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );

    # Should succeed for valid input (doesn't matter which parse tree)
    my $result = $parser->parse_string('n+n*n');
    ok $result, 'Ambiguous grammar parse returns truthy result for valid input';
    is $result->value, 1, 'Result value is 1 (true)';

    # Should fail for invalid input
    my $fail_result = $parser->parse_string('n+*n');
    is $fail_result, undef, 'Invalid syntax returns undef';
};

subtest 'Boolean vs SPPF correctness comparison' => sub {
    my $grammar = Test::Chalk::Grammar->build_grammar(
        [],
        [ 'E' => [qw(E + E)] ],
        [ 'E' => [qw(E * E)] ],
        [ 'E' => ['n'] ],
    );

    my $bool_semiring = Chalk::Semiring::Boolean->new();
    my $bool_parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $bool_semiring
    );

    my $sppf_semiring = Chalk::Semiring::SPPFViterbiSemiring->new();
    my $sppf_parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $sppf_semiring
    );

    # Test several inputs - Boolean should agree with SPPF on validity
    my @test_cases = (
        ['n', 1, 'single terminal'],
        ['n+n', 1, 'simple addition'],
        ['n*n', 1, 'simple multiplication'],
        ['n+n*n', 1, 'mixed operators'],
        ['n+', 0, 'incomplete expression'],
        ['+n', 0, 'starts with operator'],
        ['', 0, 'empty input'],
    );

    for my $case (@test_cases) {
        my ($input, $should_succeed, $desc) = @$case;

        my $bool_result = $bool_parser->parse_string($input);
        my $sppf_result = $sppf_parser->parse_string($input);

        if ($should_succeed) {
            ok $bool_result, "Boolean: $desc succeeds";
            ok $sppf_result, "SPPF: $desc succeeds";
        } else {
            ok !$bool_result, "Boolean: $desc fails";
            ok !$sppf_result, "SPPF: $desc fails";
        }

        # Both should agree on success/failure
        is !!$bool_result, !!$sppf_result, "Boolean and SPPF agree on: $desc";
    }
};

subtest 'Boolean semiring init_element_from_rule' => sub {
    my $grammar = Test::Chalk::Grammar->build_grammar(
        [],
        [ 'S' => ['a'] ],
    );

    my $semiring = Chalk::Semiring::Boolean->new();
    my $rule = ($grammar->rules_for('S'))[0];

    my $element = $semiring->init_element_from_rule($rule);
    isa_ok $element, 'Chalk::Semiring::BooleanElement';
    is $element->value, 1, 'init_element_from_rule returns element with value 1 (true)';
};

subtest 'Boolean semiring memory efficiency' => sub {
    # Boolean semiring should use minimal memory per element
    my $semiring = Chalk::Semiring::Boolean->new();

    my $elem1 = Chalk::Semiring::BooleanElement->new(value => 1);
    my $elem2 = Chalk::Semiring::BooleanElement->new(value => 0);
    my $result = $semiring->plus($elem1, $elem2);

    isa_ok $result, 'Chalk::Semiring::BooleanElement';
    is $result->value, 1, 'Result has correct value';
    # Boolean elements are lightweight - just a single scalar value
};
