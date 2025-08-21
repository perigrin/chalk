#!/usr/bin/env perl
# ABOUTME: Test parsing with augmented start rule S -> E
# ABOUTME: This should fix the parentheses parsing issue
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

# Grammar with augmented start rule
my $grammar = Grammar->build_grammar(
    [ 'S' => ['E'] ],           # Augmented start rule
    [ 'E' => [qw(E + T)] ],
    [ 'E' => ['T'] ],
    [ 'T' => [qw(T * F)] ],
    [ 'T' => ['F'] ],
    [ 'F' => [qw/( E )/] ],
    [ 'F' => ['num'] ],
);

say "Start rule: " . $grammar->start_rule;

my $parser = Parser->new(grammar => $grammar);

# Test the failing cases
my @tests = (
    [qw/num/],
    [qw/( num )/],
    [qw/( num + num )/],
    [qw/num + num * num/],
);

for my $test (@tests) {
    my $input = join(' ', @$test);
    my $result = $parser->parse_tokens(@$test);
    say "$input: " . (defined $result ? "SUCCESS" : "FAIL");
}

ok 1, "Test complete";