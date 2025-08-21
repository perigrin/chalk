#!/usr/bin/env perl
# ABOUTME: Debug trace of parsing with detailed output
# ABOUTME: Shows exactly what happens at each position
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

my $grammar = Grammar->build_grammar(
    [ 'E' => [qw(E + T)] ],
    [ 'E' => ['T'] ],
    [ 'T' => [qw(T * F)] ],
    [ 'T' => ['F'] ],
    [ 'F' => [qw/( E )/] ],
    [ 'F' => ['num'] ],
);

my @input = qw/( num )/;
my $n = scalar @input;

say "=== PARSING TRACE ===";
say "Input: " . join(' ', @input);
say "n = $n";
say "Processing positions: 0 .. $n";

# Create goal manually to check
my $goal_item = EarleyItem->new(
    start_pos => 0,
    rule      => $grammar->start_rule,
    dot_pos   => scalar($grammar->start_rule->rhs->@*),
    end_pos   => $n,
);

say "Goal item: " . $goal_item->key;
say "Start rule: " . $grammar->start_rule;

my $parser = Parser->new(grammar => $grammar);
my $result = $parser->parse(@input);

say "Final result: " . (defined $result ? "SUCCESS - $result" : "FAIL");

ok 1, "Trace complete";