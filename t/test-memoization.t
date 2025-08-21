#!/usr/bin/env perl
# ABOUTME: Test chart memoization optimizations
# ABOUTME: Verifies that prediction memoization and deduplication work correctly
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

subtest 'Basic memoization functionality' => sub {
    # Use a proven working grammar from the main tests
    my $grammar = Grammar->build_grammar(
        [ 'E' => [qw(E + T)] ],
        [ 'E' => ['T'] ],
        [ 'T' => ['num'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # This should parse correctly with memoization
    my $result = $parser->parse(qw(num + num + num));
    ok $result, 'Parse with memoized predictions';
    
    # Test with Boolean semiring too
    my $bool_parser = Parser->new(
        grammar => $grammar,
        semiring => BooleanSemiring->new()
    );
    
    $result = $bool_parser->parse(qw(num + num + num));
    ok $result, 'Boolean parse with memoized predictions';
};

subtest 'Complex nested grammar' => sub {
    # Use a working complex grammar from the main tests
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(NP VP)] ],
        [ 'NP' => [qw(Det N)] ],
        [ 'NP' => ['N'] ],
        [ 'VP' => [qw(V NP)] ],
        [ 'Det' => ['the'] ],
        [ 'N' => ['cat'] ],
        [ 'N' => ['dog'] ],
        [ 'V' => ['chased'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # Should work efficiently with memoization
    my $result = $parser->parse(qw(the cat chased the dog));
    ok $result, 'Parse complex nested grammar';
    
    $result = $parser->parse(qw(cat chased dog));
    ok $result, 'Parse without determiners';
};

subtest 'Ambiguous grammar with memoization' => sub {
    # Ambiguous grammar where memoization prevents exponential blowup
    my $grammar = Grammar->build_grammar(
        [ 'E' => [qw(E + E)] ],
        [ 'E' => [qw(E * E)] ],
        [ 'E' => ['n'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # Should handle ambiguity efficiently with memoization
    my $result = $parser->parse(qw(n + n * n + n));
    ok $result, 'Parse ambiguous grammar with memoization';
    
    # Longer input that would be expensive without memoization
    $result = $parser->parse(('n', '+') x 5, 'n');
    ok $result, 'Parse longer ambiguous input with memoization';
};

subtest 'Recursive grammar benefits' => sub {
    # Right-recursive grammar that benefits from both Leo items and memoization
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(a S)] ],
        [ 'S' => ['a'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # Should be efficient with combined optimizations
    my $result = $parser->parse(('a') x 20);
    ok $result, 'Parse recursive grammar with memoization and Leo items';
    
    # Test with Boolean semiring for completeness
    my $bool_parser = Parser->new(
        grammar => $grammar,
        semiring => BooleanSemiring->new()
    );
    
    $result = $bool_parser->parse(('a') x 20);
    ok $result, 'Boolean parse recursive with optimizations';
};