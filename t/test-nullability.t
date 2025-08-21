#!/usr/bin/env perl
# ABOUTME: Test nullability analysis for grammar optimization
# ABOUTME: Verifies correct detection of nullable nonterminals and rules
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

subtest 'Basic nullability detection' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(A B)] ],
        [ 'A' => ['a'] ],
        [ 'A' => [] ],        # epsilon production
        [ 'B' => ['b'] ],
        [ 'B' => [] ],        # epsilon production
    );
    
    
    # A and B are nullable (have epsilon productions)
    ok $grammar->is_nullable('A'), 'A is nullable (has epsilon production)';
    ok $grammar->is_nullable('B'), 'B is nullable (has epsilon production)';
    
    # S is nullable (A and B are both nullable)
    ok $grammar->is_nullable('S'), 'S is nullable (A B where both nullable)';
    
    # Terminals are not nullable
    ok !$grammar->is_nullable('a'), 'Terminal a is not nullable';
    ok !$grammar->is_nullable('b'), 'Terminal b is not nullable';
};

subtest 'Transitive nullability' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(A B C)] ],
        [ 'A' => [] ],           # epsilon
        [ 'B' => [qw(D E)] ],
        [ 'C' => ['c'] ],
        [ 'D' => [] ],           # epsilon
        [ 'E' => [] ],           # epsilon
    );
    
    
    ok $grammar->is_nullable('A'), 'A is nullable (epsilon)';
    ok $grammar->is_nullable('D'), 'D is nullable (epsilon)';
    ok $grammar->is_nullable('E'), 'E is nullable (epsilon)';
    ok $grammar->is_nullable('B'), 'B is nullable (D E both nullable)';
    ok !$grammar->is_nullable('C'), 'C is not nullable (has terminal)';
    ok !$grammar->is_nullable('S'), 'S is not nullable (C is not nullable)';
};

subtest 'No nullability' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'E' => [qw(E + T)] ],
        [ 'E' => ['T'] ],
        [ 'T' => ['num'] ],
    );
    
    
    ok !$grammar->is_nullable('E'), 'E is not nullable';
    ok !$grammar->is_nullable('T'), 'T is not nullable';
    ok !$grammar->is_nullable('num'), 'num is not nullable';
};

subtest 'Mixed nullable and non-nullable' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(A b)] ],     # Not nullable (b is terminal)
        [ 'S' => [qw(A B)] ],     # Nullable (both A and B nullable)
        [ 'A' => [] ],            # epsilon
        [ 'B' => [] ],            # epsilon
    );
    
    
    ok $grammar->is_nullable('A'), 'A is nullable';
    ok $grammar->is_nullable('B'), 'B is nullable';
    ok $grammar->is_nullable('S'), 'S is nullable (has nullable alternative)';
};

subtest 'Recursive nullability' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(S S)] ],     # Recursive but not nullable
        [ 'S' => ['a'] ],
    );
    
    
    ok !$grammar->is_nullable('S'), 'Recursive S is not nullable without epsilon';
    
    # Add epsilon rule
    my $grammar2 = Grammar->build_grammar(
        [ 'S' => [qw(S S)] ],
        [ 'S' => [] ],            # Now nullable
    );
    
    
    ok $grammar2->is_nullable('S'), 'Recursive S with epsilon is nullable';
};