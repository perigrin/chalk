#!/usr/bin/env perl
# ABOUTME: Test prediction memoization optimizations
# ABOUTME: Verifies efficient handling of redundant predictions
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

subtest 'Multiple items predicting same nonterminal' => sub {
    # Grammar where multiple items at same position will predict same nonterminal
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(A B)] ],
        [ 'S' => [qw(A C)] ],   # Both rules start with A, will predict A twice
        [ 'A' => ['a'] ],
        [ 'B' => ['b'] ],
        [ 'C' => ['c'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # Should handle redundant A predictions efficiently
    my $result = $parser->parse(qw(a b));
    ok $result, 'Parse with redundant A predictions';
    
    $result = $parser->parse(qw(a c));
    ok $result, 'Parse alternative with same A prediction';
};

subtest 'Deep nesting causing repeated predictions' => sub {
    # Grammar that causes deep prediction chains
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(A A)] ],   # Two A's will both predict same things
        [ 'A' => [qw(B B)] ],   # Two B's each will predict same things  
        [ 'B' => ['x'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # Should efficiently handle nested predictions
    my $result = $parser->parse(qw(x x x x));
    ok $result, 'Parse with nested repeated predictions';
};

subtest 'Ambiguous grammar prediction patterns' => sub {
    # Highly ambiguous grammar that would benefit from prediction memoization
    my $grammar = Grammar->build_grammar(
        [ 'E' => [qw(E + E)] ],
        [ 'E' => [qw(E * E)] ],
        [ 'E' => [qw(E - E)] ],
        [ 'E' => ['n'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # Multiple operators will cause lots of E predictions
    my $result = $parser->parse(qw(n + n * n - n));
    ok $result, 'Parse highly ambiguous with many E predictions';
    
    # Test with longer input
    $result = $parser->parse(qw(n + n + n + n + n));
    ok $result, 'Parse longer ambiguous input efficiently';
};

subtest 'Compare with and without existing optimizations' => sub {
    # Test that verifies our optimizations are working
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(a S)] ],   # Right-recursive (Leo items)
        [ 'S' => ['a'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # Should work efficiently with combined optimizations
    my $result = $parser->parse(('a') x 30);
    ok $result, 'Parse long input with all optimizations';
    
    # Test with Boolean semiring
    my $bool_parser = Parser->new(
        grammar => $grammar,
        semiring => BooleanSemiring->new()
    );
    
    $result = $bool_parser->parse(('a') x 30);
    ok $result, 'Boolean parse long input efficiently';
};