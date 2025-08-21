#!/usr/bin/env perl
# ABOUTME: Debug input parsing positions
# ABOUTME: Check if we're processing the right number of positions
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

my @input = qw/( num )/;
say "Input tokens: " . join(', ', map {"'$_'"} @input);
say "Input length: " . scalar(@input);
say "Should process positions: 0 .. " . scalar(@input);

# Test that the input tokenization is correct
my $grammar = Grammar->build_grammar(
    [ 'E' => [qw(E + T)] ],
    [ 'E' => ['T'] ],
    [ 'T' => [qw(T * F)] ],
    [ 'T' => ['F'] ],
    [ 'F' => [qw/( E )/] ],
    [ 'F' => ['num'] ],
);

my $parser = Parser->new(grammar => $grammar);
my $result = $parser->parse(@input);
say "Parse result: " . (defined $result ? "SUCCESS - $result" : "FAIL");

ok 1, "Debug complete";