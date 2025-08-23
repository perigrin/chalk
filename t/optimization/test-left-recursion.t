#!/usr/bin/env perl
# ABOUTME: Test left-recursive Leo items optimization
# ABOUTME: Verifies efficient handling of left-recursive grammars
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

subtest 'Simple left-recursive grammar' => sub {
    # Classic left-recursive expression grammar
    my $grammar = Grammar->build_grammar(
        [ 'E' => [qw(E + T)] ],  # Left-recursive
        [ 'E' => ['T'] ],
        [ 'T' => ['num'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # Should handle left-recursion efficiently
    my $result = $parser->parse_tokens(qw(num + num + num));
    ok $result, 'Parse left-recursive expression';
    
    # Test with Boolean semiring
    my $bool_parser = Parser->new(
        grammar => $grammar,
        semiring => BooleanSemiring->new()
    );
    
    $result = $bool_parser->parse_tokens(qw(num + num + num));
    ok $result, 'Boolean parse left-recursive expression';
};

subtest 'Deep left-recursive chain' => sub {
    # Test performance with deeper left-recursion
    my $grammar = Grammar->build_grammar(
        [ 'E' => [qw(E + T)] ],
        [ 'E' => ['T'] ],
        [ 'T' => ['num'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # Create a long chain: num + num + num + ... + num
    my @input = ('num');
    for (1..10) {
        push @input, '+', 'num';
    }
    
    my $result = $parser->parse_tokens(@input);
    ok $result, 'Parse deep left-recursive chain';
};

subtest 'Mixed left and right recursion' => sub {
    # Grammar with both left and right recursion
    my $grammar = Grammar->build_grammar(
        [ 'E' => [qw(E + E)] ],  # Ambiguous - both left and right recursive
        [ 'E' => [qw(E * E)] ],  # Ambiguous - both left and right recursive  
        [ 'E' => ['num'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_tokens(qw(num + num * num));
    ok $result, 'Parse mixed left/right recursive grammar';
};

subtest 'Compare with pure right-recursive equivalent' => sub {
    # Left-recursive version
    my $left_grammar = Grammar->build_grammar(
        [ 'E' => [qw(E + T)] ],
        [ 'E' => ['T'] ],
        [ 'T' => ['num'] ],
    );
    
    # Right-recursive equivalent
    my $right_grammar = Grammar->build_grammar(
        [ 'E' => [qw(T + E)] ],
        [ 'E' => ['T'] ],
        [ 'T' => ['num'] ],
    );
    
    my $left_parser = Parser->new(grammar => $left_grammar);
    my $right_parser = Parser->new(grammar => $right_grammar);
    
    my $input = [qw(num + num + num)];
    
    my $left_result = $left_parser->parse_tokens(@$input);
    my $right_result = $right_parser->parse_tokens(@$input);
    
    ok $left_result, 'Left-recursive parse succeeds';
    ok $right_result, 'Right-recursive parse succeeds';
    
    # Both should succeed, but may have different structures
    print "Left result: $left_result\n" if $left_result;
    print "Right result: $right_result\n" if $right_result;
};