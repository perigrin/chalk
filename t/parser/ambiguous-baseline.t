#!/usr/bin/env perl
# ABOUTME: Test baseline parsing of ambiguous grammars with existing semirings
# ABOUTME: Verify that ambiguous grammars work before implementing SPPF
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use lib 't/lib';
use Test::Chalk::Grammar;
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::Boolean;
use Chalk::Semiring::Viterbi;

subtest 'Simple ambiguous grammar with ViterbiSemiring' => sub {
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'E' => [qw(E + E)] ],
            [ 'E' => [qw(E * E)] ],
            [ 'E' => ['n'] ],
        ]
    );
    
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => Chalk::Semiring::Viterbi->new()
    );

    my $result = $parser->parse_string('n+n*n');
    ok $result, 'Viterbi parse ambiguous expression';
    isa_ok $result, 'Chalk::Semiring::ViterbiElement';

    # Verify Viterbi result has expected structure
    can_ok $result, 'path';
    ok scalar($result->path->@*) > 0, 'Viterbi path is non-empty';
};

subtest 'Simple ambiguous grammar with BooleanSemiring' => sub {
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'E' => [qw(E + E)] ],
            [ 'E' => [qw(E * E)] ],
            [ 'E' => ['n'] ],
        ]
    );
    
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => Chalk::Semiring::Boolean->new()
    );

    my $result = $parser->parse_string('n+n*n');
    ok $result, 'Boolean parse ambiguous expression';
    isa_ok $result, 'Chalk::Semiring::BooleanElement';
};

subtest 'More complex ambiguous expression' => sub {
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'E' => [qw(E + E)] ],
            [ 'E' => [qw(E * E)] ],
            [ 'E' => [qw(E - E)] ],
            [ 'E' => [qw(E / E)] ],
            [ 'E' => [qw(( E ))] ],
            [ 'E' => ['n'] ],
        ]
    );
    
    my $viterbi_parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => Chalk::Semiring::Viterbi->new()
    );

    my $bool_parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => Chalk::Semiring::Boolean->new()
    );
    
    # Test complex expression
    my $viterbi_result = $viterbi_parser->parse_string('n+n*n-n/n');
    ok $viterbi_result, 'Viterbi parse complex expression';

    my $bool_result = $bool_parser->parse_string('n+n*n-n/n');
    ok $bool_result, 'Boolean parse complex expression';

    # Test with parentheses
    $viterbi_result = $viterbi_parser->parse_string('(n+n)*n');
    ok $viterbi_result, 'Viterbi parse parenthesized expression';

    $bool_result = $bool_parser->parse_string('(n+n)*n');
    ok $bool_result, 'Boolean parse parenthesized expression';
    
};

subtest 'Verify existing working grammars still work' => sub {
    # Test a known working grammar from our existing tests
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'E' => [qw(E + T)] ],
            [ 'E' => ['T'] ],
            [ 'T' => ['num'] ],
        ]
    );
    
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => Chalk::Semiring::Viterbi->new()
    );
    
    my $result = $parser->parse_string('num+num+num');
    ok $result, 'Known working grammar still works';
};