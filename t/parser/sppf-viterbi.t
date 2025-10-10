#!/usr/bin/env perl
# ABOUTME: Test hybrid SPPF+Viterbi semiring implementation
# ABOUTME: Verifies Viterbi scoring with SPPF forest construction
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::SPPF;
use Chalk::Semiring::Viterbi;

subtest 'Basic SPPFViterbi functionality' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        rules => [
            [ 'E' => [qw(E + E)] ],
            [ 'E' => [qw(E * E)] ],
            [ 'E' => ['n'] ],
        ]
    );
    
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => Chalk::Semiring::SPPFViterbiSemiring->new()
    );

    my $result = $parser->parse_string('n+n*n');
    ok $result, 'SPPFViterbi parse succeeds';
    isa_ok $result, 'Chalk::Semiring::SPPFViterbiElement';
    
    # Should have both Viterbi properties
    ok defined($result->score), 'Has Viterbi score';
    ok $result->path, 'Has Viterbi path';
    
    # And SPPF properties
    ok $result->sppf_node, 'Has SPPF node';
    isa_ok $result->sppf_node, 'Chalk::Semiring::SPPFSymbolNode';
    
    print "SPPFViterbi result: $result\n";
};

subtest 'Compare with pure Viterbi' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        rules => [
            [ 'E' => [qw(E + E)] ],
            [ 'E' => [qw(E * E)] ],
            [ 'E' => ['n'] ],
        ]
    );
    
    my $sppf_viterbi_parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => Chalk::Semiring::SPPFViterbiSemiring->new()
    );

    my $viterbi_parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => Chalk::Semiring::Viterbi->new()
    );
    
    my $input = 'n+n*n';

    my $sppf_result = $sppf_viterbi_parser->parse_string($input);
    my $viterbi_result = $viterbi_parser->parse_string($input);
    
    ok $sppf_result, 'SPPF Viterbi parsing succeeds';
    ok $viterbi_result, 'Pure Viterbi parsing succeeds';
    
    # Should have same scores (approximately)
    is $sppf_result->score, $viterbi_result->score, 'Same Viterbi scores';
    
    # Should have same path lengths
    is scalar($sppf_result->path->@*), scalar($viterbi_result->path->@*), 'Same path lengths';
    
    print "SPPF Viterbi: " . $sppf_result->probability . "\n";
    print "Pure Viterbi: " . $viterbi_result->probability . "\n";
};

subtest 'SPPF forest access' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        rules => [
            [ 'E' => [qw(E + E)] ],
            [ 'E' => [qw(E * E)] ],
            [ 'E' => ['n'] ],
        ]
    );
    
    my $semiring = Chalk::Semiring::SPPFViterbiSemiring->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );
    
    my $result = $parser->parse_string('n+n*n');
    ok $result, 'Parse for forest access';
    
    # Access the forest
    my $forest = $semiring->forest();
    ok $forest, 'Can access SPPF forest';
    isa_ok $forest, 'Chalk::Semiring::SPPFForest';
    
    # Should have symbol nodes
    my $nodes_hash = $forest->nodes();
    my @nodes = values %$nodes_hash;
    ok @nodes > 0, 'Forest has symbol nodes';
    
    print "Forest has " . scalar(@nodes) . " symbol nodes\n";
    for my $node (@nodes) {
        print "  Node: $node\n";
    }
};

subtest 'Simple non-ambiguous grammar' => sub {
    # Test with a simple grammar to ensure basic functionality
    my $grammar = Chalk::Grammar->build_grammar(
        rules => [
            [ 'S' => [qw(A B)] ],
            [ 'A' => ['a'] ],
            [ 'B' => ['b'] ],
        ]
    );
    
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => Chalk::Semiring::SPPFViterbiSemiring->new()
    );
    
    my $result = $parser->parse_string('ab');
    ok $result, 'SPPFViterbi handles simple grammar';
    
    # Verify properties
    ok $result->sppf_node, 'Simple grammar has SPPF node';
    ok defined($result->score), 'Simple grammar has score';
};