#!/usr/bin/env perl
# ABOUTME: Test parsing with augmented start rule S -> E
# ABOUTME: This should fix the parentheses parsing issue
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

# Grammar with augmented start rule
my $grammar = Test::Chalk::Grammar->build_grammar(
    rules => [
        [ 'S' => ['E'] ],           # Augmented start rule
        [ 'E' => [qw(E + T)] ],
        [ 'E' => ['T'] ],
        [ 'T' => [qw(T * F)] ],
        [ 'T' => ['F'] ],
        [ 'F' => [qw/( E )/] ],
        [ 'F' => ['num'] ],
    ]
);

is $grammar->start_symbol, 'S', 'Start symbol is augmented S rule';

my $parser = Chalk::Parser->new(grammar => $grammar);

# Test the failing cases with proper assertions
my @tests = (
    { input => [qw/num/], desc => 'Parse single number' },
    { input => [qw/( num )/], desc => 'Parse parenthesized number' },
    { input => [qw/( num + num )/], desc => 'Parse parenthesized addition' },
    { input => [qw/num + num * num/], desc => 'Parse expression with precedence' },
);

for my $test (@tests) {
    my $input_str = join('', $test->{input}->@*);
    my $result = $parser->parse_string($input_str);
    ok $result, $test->{desc} . ": $input_str";
    isa_ok $result, ['Chalk::Element'], 'Result is a semiring element' if $result;
}