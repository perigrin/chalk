#!/usr/bin/env perl
# ABOUTME: Test left-recursion performance to identify if Leo optimization needed
# ABOUTME: Compare performance characteristics of left vs right recursion
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
use Time::HiRes qw(time);
defer { done_testing() }

require "$RealBin/../chalk";

subtest 'Performance comparison: left vs right recursion' => sub {
    # Left-recursive grammar
    my $left_grammar = Grammar->build_grammar(
        [ 'E' => [qw(E + T)] ],
        [ 'E' => ['T'] ],
        [ 'T' => ['a'] ],
    );
    
    # Right-recursive grammar (has Leo optimization)
    my $right_grammar = Grammar->build_grammar(
        [ 'E' => [qw(T + E)] ],
        [ 'E' => ['T'] ],
        [ 'T' => ['a'] ],
    );
    
    my $left_parser = Parser->new(grammar => $left_grammar);
    my $right_parser = Parser->new(grammar => $right_grammar);
    
    # Test with progressively longer inputs
    for my $length (5, 10, 15, 20) {
        my @input = ('a');
        push @input, '+', 'a' for (2..$length);
        
        # Time left-recursive parsing
        my $left_start = time();
        my $left_result = $left_parser->parse(@input);
        my $left_time = time() - $left_start;
        
        # Time right-recursive parsing
        my $right_start = time();
        my $right_result = $right_parser->parse(@input);
        my $right_time = time() - $right_start;
        
        ok $left_result, "Left recursion handles length $length";
        ok $right_result, "Right recursion handles length $length";
        
        printf "Length %d: Left=%.4fs, Right=%.4fs, Ratio=%.2fx\n", 
               $length, $left_time, $right_time, 
               $right_time > 0 ? $left_time / $right_time : 0;
    }
};

subtest 'Stress test left-recursion' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'E' => [qw(E + T)] ],
        [ 'E' => ['T'] ],
        [ 'T' => ['a'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # Test with very long input to see if we hit performance issues
    my @input = ('a');
    push @input, '+', 'a' for (2..50);
    
    my $start = time();
    my $result = $parser->parse(@input);
    my $elapsed = time() - $start;
    
    ok $result, 'Left recursion handles 50-element chain';
    printf "50-element chain: %.4fs\n", $elapsed;
    
    # If this takes more than 1 second, we probably need Leo optimization
    if ($elapsed > 1.0) {
        diag "Left-recursion seems slow - Leo optimization might help";
    }
};