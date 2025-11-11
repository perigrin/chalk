#!/usr/bin/env perl
# ABOUTME: Basic parser smoke test verifying minimal grammar and parsing functionality
# ABOUTME: Tests that a single-rule grammar can be created and a simple string can be parsed
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use lib 't/lib';
use Test::Chalk::Grammar;
use Chalk::Grammar;
use Chalk::Parser;

my $grammar = Test::Chalk::Grammar->build_grammar(
    rules => [
        [ 'A' => [] ]
    ]
);
ok $grammar, 'Grammar created successfully';

my $parser = Chalk::Parser->new( grammar => $grammar );
my $result = $parser->parse_string('');  # A => [] produces empty string
ok $result, 'Parse empty string with minimal grammar';
isa_ok $result, ['Chalk::Element'], 'Result is a semiring element';

