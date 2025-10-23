#!/usr/bin/env perl
# ABOUTME: Test simple arithmetic grammar
# ABOUTME: Focuses on basic arithmetic parsing to isolate issues
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use lib "$RealBin/../../lib";
use experimental qw(defer);
use lib 't/lib';
use Test::Chalk::Grammar;
use Chalk::Grammar;
use Chalk::Parser;
defer { done_testing() }

# Simple arithmetic
my $grammar = Test::Chalk::Grammar->build_grammar(
    rules => [
        [ 'E' => ['num'] ],
    ]
);

my $parser = Chalk::Parser->new(grammar => $grammar);

my $result = $parser->parse_string('num');
say "Single num result: " . (defined $result ? ref($result) . " - $result" : "undef");

ok $result, "Parse single num";

# Now try with addition
$grammar = Test::Chalk::Grammar->build_grammar(
    rules => [
        [ 'E' => [qw(E + E)] ],
        [ 'E' => ['num'] ],
    ]
);

$parser = Chalk::Parser->new(grammar => $grammar);
$result = $parser->parse_string('num+num');
say "Addition result: " . (defined $result ? ref($result) . " - $result" : "undef");

ok $result, "Parse num + num";