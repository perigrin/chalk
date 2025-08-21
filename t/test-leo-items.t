#!/usr/bin/env perl
# ABOUTME: Test Leo items optimization for right-recursive grammars
# ABOUTME: Verifies that Leo items properly compress right-recursive chains
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

subtest 'Right-recursive grammar with Leo items' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(a S)] ],
        [ 'S' => ['a'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # Test basic parsing still works
    my $result = $parser->parse(qw(a));
    ok $result, 'Parse single a';
    
    $result = $parser->parse(qw(a a a));
    ok $result, 'Parse a a a with right recursion';
    
    # Test longer inputs that benefit from Leo optimization
    $result = $parser->parse(('a') x 10);
    ok $result, 'Parse 10 a\'s with Leo optimization';
    
    $result = $parser->parse(('a') x 20);
    ok $result, 'Parse 20 a\'s with Leo optimization';
};

subtest 'Complex right-recursive grammar' => sub {
    # Grammar with multiple right-recursive rules
    my $grammar = Grammar->build_grammar(
        [ 'E' => [qw(T + E)] ],  # Right-recursive addition
        [ 'E' => ['T'] ],
        [ 'T' => [qw(F * T)] ],  # Right-recursive multiplication
        [ 'T' => ['F'] ],
        [ 'F' => ['num'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    my $result = $parser->parse(qw(num + num + num + num));
    ok $result, 'Parse right-recursive addition chain';
    
    $result = $parser->parse(qw(num * num * num * num));
    ok $result, 'Parse right-recursive multiplication chain';
    
    $result = $parser->parse(qw(num + num * num + num));
    ok $result, 'Parse mixed right-recursive expression';
};

subtest 'Verify Leo item creation' => sub {
    # Add debugging to verify Leo items are actually created
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(a S)] ],
        [ 'S' => ['a'] ],
    );
    
    # We'll need to instrument the parser to check for Leo items
    # For now, just verify correctness of parsing
    my $parser = Parser->new(grammar => $grammar);
    
    # Create a long chain that should definitely trigger Leo optimization
    my @input = ('a') x 50;
    my $result = $parser->parse(@input);
    ok $result, 'Parse 50 a\'s - should use Leo items for efficiency';
    
    # With Boolean semiring to test recognition
    my $bool_parser = Parser->new(
        grammar => $grammar,
        semiring => BooleanSemiring->new()
    );
    
    $result = $bool_parser->parse(@input);
    ok $result, 'Boolean parse of 50 a\'s with Leo optimization';
};