#!/usr/bin/env perl
# ABOUTME: Test zero-length regex matches in lexeme parsing
# ABOUTME: Verify that qr/\s*/ and other zero-length patterns work correctly
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;

subtest 'Zero-length whitespace patterns' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'Test' => ['WS_OPT', 'word', 'WS_OPT'] ],
        [ 'WS_OPT' => [qr/\s*/] ],  # Zero-length whitespace pattern
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    # Test with no whitespace (zero-length matches at start and end)
    todo "zero-length matches not yet supported" => sub {
        my $result = $parser->parse_string('word');
        ok $result, 'Parse with zero-length whitespace matches';
    };
    
    # Test with actual whitespace
    my $result = $parser->parse_string(' word ');
    ok $result, 'Parse with actual whitespace';
    
    # Test with only leading whitespace
    todo "zero-length matches not yet supported" => sub {
        $result = $parser->parse_string(' word');
        ok $result, 'Parse with leading whitespace only';
    };
    
    # Test with only trailing whitespace
    todo "zero-length matches not yet supported" => sub {
        $result = $parser->parse_string('word ');
        ok $result, 'Parse with trailing whitespace only';
    };
};

subtest 'Optional patterns' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'Test' => ['prefix', 'OPT_SUFFIX'] ],
        [ 'OPT_SUFFIX' => [qr/suffix?/] ],  # Optional 's' at end
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    todo "zero-length matches not yet supported" => sub {
        my $result = $parser->parse_string('prefix');
        ok $result, 'Parse without optional suffix';
    };
    
    my $result = $parser->parse_string('prefixsuffix');
    ok $result, 'Parse with optional suffix present';
};

subtest 'Mixed zero-length and regular patterns' => sub {
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'Statement' => ['WS_OPT', 'word', 'WS', 'word', 'WS_OPT', 'SEMI_OPT'] ],
        [ 'WS' => [qr/\s+/] ],           # Required whitespace
        [ 'WS_OPT' => [qr/\s*/] ],       # Optional whitespace  
        [ 'SEMI_OPT' => [qr/;?/] ],      # Optional semicolon
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    # Minimal case
    todo "zero-length matches not yet supported" => sub {
        my $result = $parser->parse_string('hello world');
        ok $result, 'Parse minimal statement';
    };
    
    # With optional elements
    todo "zero-length matches not yet supported" => sub {
        my $result = $parser->parse_string(' hello world ;');
        ok $result, 'Parse statement with optional whitespace and semicolon';
    };
    
    # With extra whitespace
    todo "zero-length matches not yet supported" => sub {
        my $result = $parser->parse_string('  hello   world  ');
        ok $result, 'Parse statement with extra whitespace';
    };
};