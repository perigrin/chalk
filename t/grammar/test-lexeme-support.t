#!/usr/bin/env perl
# ABOUTME: Test lexeme/regex support in parse_string() method
# ABOUTME: Verify that terminals can be regex patterns instead of exact tokens
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all defer);
use utf8;
use open qw/:std :utf8/;
use Test2::V0;
use FindBin qw($RealBin);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;

subtest 'Basic lexeme support' => sub {
    # Test with exact string literals (should work like before)
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'Rule' => ['hello', 'world'] ]
    );
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('helloworld');
    ok $result, 'Parse string with exact literals';
};

subtest 'Regex pattern support' => sub {
    # Test with regex patterns for identifiers
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'Rule' => [qr/[a-zA-Z]+/, qr/\d+/] ]
    );
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('hello123');
    ok $result, 'Parse string with regex patterns';
    
    $result = $parser->parse_string('abc456');
    ok $result, 'Parse another string with regex patterns';
};

subtest 'Mixed literals and patterns' => sub {
    # Test mixing exact strings and patterns
    my $grammar = Chalk::Grammar->build_grammar(
        [ 'Rule' => ['class', qr/[a-zA-Z_][a-zA-Z0-9_]*/, '{', '}'] ]
    );
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('classElement{}');
    ok $result, 'Parse with mixed literals and patterns';
    
    $result = $parser->parse_string('class_MyClass{}');
    ok $result, 'Parse another mixed example';
};