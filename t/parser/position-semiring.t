#!/usr/bin/env perl
# ABOUTME: Test Position semiring implementation for position tracking validation
# ABOUTME: Verifies position span tracking and incomplete parse detection

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Base;
use Chalk::Semiring::Position;
use Chalk::Grammar;
use Chalk::Parser;

subtest 'Position semiring element creation' => sub {
    my $elem = Chalk::Semiring::PositionElement->new(
        start_pos => 0,
        end_pos => 5
    );

    is $elem->start_pos, 0, 'start_pos accessor works';
    is $elem->end_pos, 5, 'end_pos accessor works';
    is $elem->to_string, '[0,5]', 'to_string shows span';
};

subtest 'Position semiring algebra - multiply (sequence)' => sub {
    my $elem1 = Chalk::Semiring::PositionElement->new(start_pos => 0, end_pos => 3);
    my $elem2 = Chalk::Semiring::PositionElement->new(start_pos => 3, end_pos => 7);

    my $result = $elem1->multiply($elem2);

    is $result->start_pos, 0, 'Sequence: start from first element';
    is $result->end_pos, 7, 'Sequence: end from second element';
    is $result->to_string, '[0,7]', 'Sequence combines spans [0,3] * [3,7] = [0,7]';
};

subtest 'Position semiring algebra - add (choice)' => sub {
    my $elem1 = Chalk::Semiring::PositionElement->new(start_pos => 0, end_pos => 3);
    my $elem2 = Chalk::Semiring::PositionElement->new(start_pos => 0, end_pos => 7);

    my $result = $elem1->add($elem2);

    # Choice: prefer the parse that went further
    is $result->start_pos, 0, 'Choice: start position preserved';
    is $result->end_pos, 7, 'Choice: takes longer parse (7 > 3)';
    is $result->to_string, '[0,7]', 'Choice prefers parse that went further';
};

subtest 'Position semiring identity elements' => sub {
    my $semiring = Chalk::Semiring::Position->new();

    is $semiring->mul_id->start_pos, 0, 'Multiplicative identity starts at 0';
    is $semiring->mul_id->end_pos, 0, 'Multiplicative identity ends at 0 (epsilon)';

    is $semiring->add_id->start_pos, 0, 'Additive identity starts at 0';
    is $semiring->add_id->end_pos, 0, 'Additive identity ends at 0 (no parse)';
};

subtest 'Position semiring with simple grammar - complete parse' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        [],
        [ 'S' => [qw(a b)] ],
    );

    my $semiring = Chalk::Semiring::Position->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );

    my $result = $parser->parse_string('ab');
    ok $result, 'Valid parse returns result';
    is $result->start_pos, 0, 'Parse starts at position 0';
    is $result->end_pos, 2, 'Parse ends at position 2 (complete)';
    is $result->to_string, '[0,2]', 'Complete parse spans entire input';
};

subtest 'Position semiring detects incomplete parse' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        [],
        [ 'S' => [qw(a b c)] ],
    );

    my $semiring = Chalk::Semiring::Position->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );

    # Input 'ab' but grammar expects 'abc'
    my $result = $parser->parse_string('ab');

    # TODO: Future enhancement - return partial result showing furthest position reached
    # For now, incomplete parses return undef (same as Boolean semiring)
    ok !$result, 'Incomplete parse returns undef (no complete derivation found)';
};
