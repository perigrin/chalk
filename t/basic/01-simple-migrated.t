#!/usr/bin/env perl
# ABOUTME: Test basic empty rule grammar using modern Chalk::Grammar library
# ABOUTME: Validates that simple grammars can be created and parsed
use 5.40.0;
use Test2::V0;
use lib 'lib';
use Chalk::Grammar;
use Chalk::Parser;
use experimental qw(defer);
defer { done_testing() }

my $grammar = Chalk::Grammar->build_grammar(
    rules => [
        [ 'A' => [] ]
    ]
);
ok $grammar, $grammar;

my $parser = Chalk::Parser->new( grammar => $grammar );
$parser->parse_string('A');