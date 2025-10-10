#!/usr/bin/env perl
# ABOUTME: Test suite for Parser with various grammar types
# ABOUTME: Validates parsing correctness across different grammar structures
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;

subtest 'Basic arithmetic grammar' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'E' => [qw(E + T)] ],
        [ 'E' => ['T'] ],
        [ 'T' => [qw(T * F)] ],
        [ 'T' => ['F'] ],
        [ 'F' => [qw/( E )/] ],
        [ 'F' => ['num'] ],
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('num+num*num');
    ok $result, 'Parse num + num * num';

    $result = $parser->parse_string('(num+num)');
    ok $result, 'Parse ( num + num )';

    $result = $parser->parse_string('((num))');
    ok $result, 'Parse ( ( num ) )';
};

subtest 'Ambiguous grammar' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'E' => [qw(E + E)] ],
        [ 'E' => [qw(E * E)] ],
        [ 'E' => ['num'] ],
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('num+num*num');
    ok $result, 'Parse ambiguous num + num * num';

    # With ViterbiSemiring, should pick best path
    my $viterbi_parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => ViterbiSemiring->new()
    );

    $result = $viterbi_parser->parse_string('num+num*num');
    ok $result, 'Viterbi parse ambiguous expression';
    isa_ok $result, 'ViterbiElement';
};

subtest 'Left-recursive grammar' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'S' => [qw(S a)] ],
        [ 'S' => ['a'] ],
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('a');
    ok $result, 'Parse single a';

    $result = $parser->parse_string('aaa');
    ok $result, 'Parse a a a with left recursion';
};

subtest 'Right-recursive grammar' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'S' => [qw(a S)] ],
        [ 'S' => ['a'] ],
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('a');
    ok $result, 'Parse single a';

    $result = $parser->parse_string('aaa');
    ok $result, 'Parse a a a with right recursion';
};

subtest 'Empty productions' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'S' => [qw(A B)] ],
        [ 'A' => ['a'] ],
        [ 'A' => [] ],  # epsilon
        [ 'B' => ['b'] ],
        [ 'B' => [] ],  # epsilon
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('ab');
    ok $result, 'Parse a b';

    $result = $parser->parse_string('a');
    ok $result, 'Parse a (B -> epsilon)';

    $result = $parser->parse_string('b');
    ok $result, 'Parse b (A -> epsilon)';

    $result = $parser->parse_string('');
    ok $result, 'Parse empty (both epsilon)';
};

subtest 'Boolean vs Viterbi semiring' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'S' => ['A'] ],
        [ 'A' => ['a'] ],
    );
    
    my $bool_parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => BooleanSemiring->new()
    );
    
    my $viterbi_parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => ViterbiSemiring->new()
    );
    
    my $bool_result = $bool_parser->parse_string('a');
    ok $bool_result, 'Boolean parse succeeds';
    isa_ok $bool_result, 'BooleanElement';

    my $viterbi_result = $viterbi_parser->parse_string('a');
    ok $viterbi_result, 'Viterbi parse succeeds';
    isa_ok $viterbi_result, 'ViterbiElement';
    
    # Viterbi should have path information
    ok $viterbi_result->path, 'Viterbi has path';
    is scalar($viterbi_result->path->@*), 2, 'Path has 2 rules';
};

subtest 'Complex nested grammar' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'S' => [qw(NP VP)] ],
        [ 'NP' => [qw(Det N)] ],
        [ 'NP' => ['N'] ],
        [ 'VP' => [qw(V NP)] ],
        [ 'Det' => ['the'] ],
        [ 'N' => ['cat'] ],
        [ 'N' => ['dog'] ],
        [ 'V' => ['chased'] ],
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('thecatchasedthedog');
    ok $result, 'Parse the cat chased the dog';

    $result = $parser->parse_string('catchaseddog');
    ok $result, 'Parse cat chased dog (no determiners)';
};

subtest 'Invalid input rejection' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'S' => ['a'] ],
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('b');
    ok !$result, 'Reject invalid terminal';

    $result = $parser->parse_string('aa');
    ok !$result, 'Reject too many tokens';
};