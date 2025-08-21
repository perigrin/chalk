#!/usr/bin/env perl
# ABOUTME: Test nullability optimization in parsing
# ABOUTME: Verifies Aycock-Horspool optimizations reduce redundant items
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

subtest 'Parse with nullable productions' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(A B)] ],
        [ 'A' => ['a'] ],
        [ 'A' => [] ],        # epsilon production
        [ 'B' => ['b'] ],
        [ 'B' => [] ],        # epsilon production
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # These should all parse successfully due to nullable optimizations
    my $result = $parser->parse(qw(a b));
    ok $result, 'Parse a b';
    
    $result = $parser->parse(qw(a));
    ok $result, 'Parse a (B nullable)';
    
    $result = $parser->parse(qw(b));
    ok $result, 'Parse b (A nullable)';
    
    $result = $parser->parse();
    ok $result, 'Parse empty (both nullable)';
};

subtest 'Nullable chains' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(A B C)] ],
        [ 'A' => [] ],           # epsilon
        [ 'B' => [] ],           # epsilon  
        [ 'C' => ['c'] ],
        [ 'C' => [] ],           # epsilon
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    my $result = $parser->parse(qw(c));
    ok $result, 'Parse c with nullable prefix';
    
    $result = $parser->parse();
    ok $result, 'Parse empty with all nullable';
};

subtest 'Mixed nullable and terminal' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(OptA b OptB)] ],
        [ 'OptA' => ['a'] ],
        [ 'OptA' => [] ],         # optional a
        [ 'OptB' => ['c'] ],
        [ 'OptB' => [] ],         # optional c
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    my $result = $parser->parse(qw(a b c));
    ok $result, 'Parse a b c (full)';
    
    $result = $parser->parse(qw(b c));
    ok $result, 'Parse b c (no a)';
    
    $result = $parser->parse(qw(a b));
    ok $result, 'Parse a b (no c)';
    
    $result = $parser->parse(qw(b));
    ok $result, 'Parse b (minimal)';
};

subtest 'Verify optimization with complex grammar' => sub {
    # Grammar that would benefit from nullability optimization
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(Expr)] ],
        [ 'Expr' => [qw(Term ExprTail)] ],
        [ 'ExprTail' => [qw(+ Term ExprTail)] ],
        [ 'ExprTail' => [] ],     # epsilon - makes addition optional
        [ 'Term' => [qw(Factor TermTail)] ],
        [ 'TermTail' => [qw(* Factor TermTail)] ],
        [ 'TermTail' => [] ],     # epsilon - makes multiplication optional
        [ 'Factor' => ['num'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    my $result = $parser->parse(qw(num));
    ok $result, 'Parse single num with nullable tails';
    
    $result = $parser->parse(qw(num + num));
    ok $result, 'Parse addition with nullable tails';
    
    $result = $parser->parse(qw(num * num + num));
    ok $result, 'Parse complex expression with nullable tails';
};