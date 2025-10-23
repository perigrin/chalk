#!/usr/bin/env perl
# ABOUTME: Test that the '0' token parsing bug is fixed
# ABOUTME: Regression test for falsiness vs definedness issue
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all defer);
use utf8;
use open qw/:std :utf8/;
use Test2::V0;
use FindBin qw($RealBin);
defer { done_testing() }

use lib "$RealBin/../../lib";
use lib 't/lib';
use Test::Chalk::Grammar;
use Chalk::Grammar;
use Chalk::Parser;

subtest 'Zero token regression test' => sub {
    # This was the original failing case - '0' token would fail due to falsiness
    my $grammar = Test::Chalk::Grammar->build_grammar(rules => [ [ 'Rule' => ['0'] ] ]);
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('0');
    ok $result, "Parse '0' token succeeds";
    isa_ok $result, ['Chalk::Semiring::SPPFViterbiElement'], "Result is SPPFViterbiElement";
    
    # Verify the actual parse result makes sense
    like $result->to_string, qr/Rule -> 0/, "Parse contains expected rule";
};

subtest 'Other falsy values still work' => sub {
    # Make sure we didn't break other falsy values
    my $grammar = Test::Chalk::Grammar->build_grammar(rules => [ [ 'Rule' => [''] ] ]);
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('');
    ok $result, "Parse empty string succeeds";
};

subtest 'Compare with truthy values' => sub {
    # Sanity check that truthy values still work
    my $grammar = Test::Chalk::Grammar->build_grammar(rules => [ [ 'Rule' => ['1'] ] ]);
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('1');
    ok $result, "Parse '1' token succeeds";
    like $result->to_string, qr/Rule -> 1/, "Parse contains expected rule";
};