#!/usr/bin/env perl
# ABOUTME: Test baseline parsing of ambiguous grammars with existing semirings
# ABOUTME: Verify that ambiguous grammars work before implementing SPPF
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;

subtest 'Simple ambiguous grammar with ViterbiSemiring' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'E' => [qw(E + E)] ],
        [ 'E' => [qw(E * E)] ],
        [ 'E' => ['n'] ],
    );
    
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => ViterbiSemiring->new()
    );
    
    my $result = $parser->parse_string('n+n*n');
    ok $result, 'Viterbi parse ambiguous expression';
    isa_ok $result, 'ViterbiElement';
    
    print "Viterbi result: $result\n";
    print "Path: " . join(", ", map { $_->to_string } $result->path->@*) . "\n";
};

subtest 'Simple ambiguous grammar with BooleanSemiring' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'E' => [qw(E + E)] ],
        [ 'E' => [qw(E * E)] ],
        [ 'E' => ['n'] ],
    );
    
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => BooleanSemiring->new()
    );
    
    my $result = $parser->parse_string('n+n*n');
    ok $result, 'Boolean parse ambiguous expression';
    isa_ok $result, 'BooleanElement';
    
    print "Boolean result: $result\n";
};

subtest 'More complex ambiguous expression' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'E' => [qw(E + E)] ],
        [ 'E' => [qw(E * E)] ],
        [ 'E' => [qw(E - E)] ],
        [ 'E' => [qw(E / E)] ],
        [ 'E' => [qw(( E ))] ],
        [ 'E' => ['n'] ],
    );
    
    my $viterbi_parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => ViterbiSemiring->new()
    );
    
    my $bool_parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => BooleanSemiring->new()
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
    
    print "Complex Viterbi result: $viterbi_result\n" if $viterbi_result;
    print "Complex Boolean result: $bool_result\n" if $bool_result;
};

subtest 'Verify existing working grammars still work' => sub {
    # Test a known working grammar from our existing tests
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'E' => [qw(E + T)] ],
        [ 'E' => ['T'] ],
        [ 'T' => ['num'] ],
    );
    
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => ViterbiSemiring->new()
    );
    
    my $result = $parser->parse_string('num+num+num');
    ok $result, 'Known working grammar still works';
    print "Working grammar result: $result\n" if $result;
};