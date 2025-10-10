#!/usr/bin/env perl
# ABOUTME: Test suite for Aycock-Horspool left-recursion handling
# ABOUTME: Tests indirect recursion, hidden recursion, and seed/grow phases
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

subtest 'Direct left-recursion (baseline)' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(S a)] ],
        [ 'S' => ['a'] ],
    );

    my $parser = Parser->new(grammar => $grammar);

    my $result = $parser->parse_string('a');
    ok $result, 'Parse single a with direct left-recursion';

    $result = $parser->parse_string('aaa');
    ok $result, 'Parse aaa with direct left-recursion';
};

subtest 'Indirect left-recursion (A -> B alpha, B -> A beta)' => sub {
    # Grammar with indirect left-recursion cycle:
    # A -> B a
    # B -> A b
    # A -> c
    # B -> d
    my $grammar = Grammar->build_grammar(
        [ 'A' => [qw(B a)] ],
        [ 'B' => [qw(A b)] ],
        [ 'A' => ['c'] ],
        [ 'B' => ['d'] ],
    );

    my $parser = Parser->new(grammar => $grammar);

    # These should parse successfully:
    # A -> c
    my $result = $parser->parse_string('c');
    ok $result, 'Parse c (A -> c)';

    # A -> B a, B -> d
    $result = $parser->parse_string('da');
    ok $result, 'Parse da (A -> B a, B -> d)';

    # A -> B a, B -> A b, A -> c
    $result = $parser->parse_string('cba');
    ok $result, 'Parse cba (A -> B a, B -> A b, A -> c)';

    # A -> B a, B -> A b, A -> B a, B -> A b, A -> c
    # Derivation: A -> Ba -> (Ab)a -> ((Ba)b)a -> (((Ab)a)b)a -> ((((c)b)a)b)a = cbaba
    $result = $parser->parse_string('cbaba');
    ok $result, 'Parse cbaba (deeper indirect recursion)';
};

subtest 'Indirect left-recursion (three-way cycle)' => sub {
    # Grammar with three-way indirect left-recursion:
    # A -> B x
    # B -> C y
    # C -> A z
    # A -> w
    my $grammar = Grammar->build_grammar(
        [ 'A' => [qw(B x)] ],
        [ 'B' => [qw(C y)] ],
        [ 'C' => [qw(A z)] ],
        [ 'A' => ['w'] ],
    );

    my $parser = Parser->new(grammar => $grammar);

    # A -> w
    my $result = $parser->parse_string('w');
    ok $result, 'Parse w (A -> w)';

    # A -> B x, B -> C y, C -> A z, A -> w
    $result = $parser->parse_string('wzyx');
    ok $result, 'Parse wzyx (three-way cycle)';

    # A -> B x, B -> C y, C -> A z, A -> B x, B -> C y, ...
    $result = $parser->parse_string('wzyxzyxzyx');
    ok $result, 'Parse wzyxzyxzyx (multiple cycles)';
};

subtest 'Hidden left-recursion through nullable symbols' => sub {
    # Grammar where B is nullable:
    # A -> B A a
    # A -> b
    # B -> c
    # B -> (epsilon)
    my $grammar = Grammar->build_grammar(
        [ 'A' => [qw(B A a)] ],
        [ 'A' => ['b'] ],
        [ 'B' => ['c'] ],
        [ 'B' => [] ],  # epsilon - makes B nullable
    );

    my $parser = Parser->new(grammar => $grammar);

    # A -> b
    my $result = $parser->parse_string('b');
    ok $result, 'Parse b (base case)';

    # A -> B A a, B -> epsilon, A -> b (effectively A -> A a)
    $result = $parser->parse_string('ba');
    ok $result, 'Parse ba (hidden left-recursion through nullable B)';

    # A -> B A a, B -> c, A -> b
    $result = $parser->parse_string('cba');
    ok $result, 'Parse cba (with non-nullable B)';

    # Multiple levels of hidden recursion
    $result = $parser->parse_string('baa');
    ok $result, 'Parse baa (multiple hidden recursion)';

    # A -> B A a, B -> epsilon, A -> B A a, B -> c, A -> b
    $result = $parser->parse_string('cbaa');
    ok $result, 'Parse cbaa (mixed nullable and non-nullable)';
};

subtest 'Hidden left-recursion with multiple nullable symbols' => sub {
    # Grammar with multiple nullable symbols creating hidden left-recursion:
    # S -> X Y S a
    # S -> b
    # X -> c
    # X -> (epsilon)
    # Y -> d
    # Y -> (epsilon)
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(X Y S a)] ],
        [ 'S' => ['b'] ],
        [ 'X' => ['c'] ],
        [ 'X' => [] ],
        [ 'Y' => ['d'] ],
        [ 'Y' => [] ],
    );

    my $parser = Parser->new(grammar => $grammar);

    # S -> b
    my $result = $parser->parse_string('b');
    ok $result, 'Parse b (base case)';

    # S -> X Y S a, X -> epsilon, Y -> epsilon, S -> b (effectively S -> S a)
    $result = $parser->parse_string('ba');
    ok $result, 'Parse ba (both X and Y nullable)';

    # S -> X Y S a, X -> c, Y -> epsilon, S -> b
    $result = $parser->parse_string('cba');
    ok $result, 'Parse cba (X non-nullable, Y nullable)';

    # S -> X Y S a, X -> epsilon, Y -> d, S -> b
    $result = $parser->parse_string('dba');
    ok $result, 'Parse dba (X nullable, Y non-nullable)';

    # S -> X Y S a, X -> c, Y -> d, S -> b
    $result = $parser->parse_string('cdba');
    ok $result, 'Parse cdba (both non-nullable)';

    # Multiple recursion levels
    $result = $parser->parse_string('baa');
    ok $result, 'Parse baa (multiple hidden recursion)';
};

subtest 'Seed and grow phases for left-recursive parsing' => sub {
    # Classic left-recursive expression grammar
    # This tests that we properly seed with base cases and grow
    my $grammar = Grammar->build_grammar(
        [ 'E' => [qw(E + T)] ],  # Left-recursive
        [ 'E' => ['T'] ],         # Base case (seed)
        [ 'T' => ['num'] ],
    );

    my $parser = Parser->new(grammar => $grammar);

    # Seed: E -> T, T -> num
    my $result = $parser->parse_string('num');
    ok $result, 'Parse num (seed phase)';

    # Grow once: E -> E + T, E -> T, T -> num
    $result = $parser->parse_string('num+num');
    ok $result, 'Parse num+num (grow phase - one iteration)';

    # Grow multiple times
    $result = $parser->parse_string('num+num+num');
    ok $result, 'Parse num+num+num (grow phase - two iterations)';

    # Longer chain to verify seed/grow works correctly
    $result = $parser->parse_string('num+num+num+num+num');
    ok $result, 'Parse num+num+num+num+num (grow phase - four iterations)';
};

subtest 'Seed and grow with multiple left-recursive rules' => sub {
    # Grammar with multiple left-recursive alternatives
    my $grammar = Grammar->build_grammar(
        [ 'E' => [qw(E + E)] ],   # Left-recursive addition
        [ 'E' => [qw(E * E)] ],   # Left-recursive multiplication
        [ 'E' => ['num'] ],       # Base case (seed)
    );

    my $parser = Parser->new(grammar => $grammar);

    # Seed
    my $result = $parser->parse_string('num');
    ok $result, 'Parse num (seed with multiple alternatives)';

    # Grow with addition
    $result = $parser->parse_string('num+num');
    ok $result, 'Parse num+num (grow with addition)';

    # Grow with multiplication
    $result = $parser->parse_string('num*num');
    ok $result, 'Parse num*num (grow with multiplication)';

    # Mixed operations (tests that both alternatives can grow)
    $result = $parser->parse_string('num+num*num');
    ok $result, 'Parse num+num*num (multiple alternatives growing)';

    $result = $parser->parse_string('num*num+num*num');
    ok $result, 'Parse num*num+num*num (complex mixed growth)';
};

subtest 'Combined indirect and hidden left-recursion' => sub {
    # Complex grammar combining both indirect and hidden recursion
    # A -> B A x
    # B -> C
    # C -> A y
    # C -> (epsilon)
    # A -> z
    my $grammar = Grammar->build_grammar(
        [ 'A' => [qw(B A x)] ],
        [ 'B' => ['C'] ],
        [ 'C' => [qw(A y)] ],
        [ 'C' => [] ],      # makes C (and thus B) nullable
        [ 'A' => ['z'] ],
    );

    my $parser = Parser->new(grammar => $grammar);

    # A -> z
    my $result = $parser->parse_string('z');
    ok $result, 'Parse z (base case)';

    # A -> B A x, B -> C, C -> epsilon, A -> z (hidden recursion)
    $result = $parser->parse_string('zx');
    ok $result, 'Parse zx (hidden recursion through nullable B)';

    # A -> B A x, B -> C, C -> A y, A -> z (indirect recursion through cycle)
    # Derivation: A -> BAx -> CAx -> (Ay)Ax -> zy(BAx)x -> zy(CAx)x -> zy(εAx)x -> zyzxx
    $result = $parser->parse_string('zyzxx');
    ok $result, 'Parse zyzxx (indirect recursion through B and C)';

    # Multiple levels of hidden recursion: A -> BAx -> CAx -> εAx -> (BAx)x -> ... -> zxxx
    $result = $parser->parse_string('zxxx');
    ok $result, 'Parse zxxx (multiple hidden recursion levels)';
};
