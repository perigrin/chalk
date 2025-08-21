#!/usr/bin/env perl
# ABOUTME: Trace test to understand parse step by step
# ABOUTME: Adds debugging output to see exactly what happens during parsing
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

# Simple grammar: S -> a
my $grammar = Grammar->build_grammar(
    [ 'S' => ['a'] ],
);

my $parser = Parser->new(grammar => $grammar);

say "=== Parsing 'a' ===";

# Manual step through
my @input = qw(a);
my $n = scalar @input;

say "Input length: $n";
say "Start rule: " . $grammar->start_rule;

# Check goal item construction
my $goal_item = EarleyItem->new(
    start_pos => 0,
    rule      => $grammar->start_rule,
    dot_pos   => scalar($grammar->start_rule->rhs->@*),
    end_pos   => $n,
);
say "Goal item: $goal_item";
say "Goal key: " . $goal_item->key;

my $result = $parser->parse(@input);
say "Final result: " . (defined $result ? ref($result) . " - $result" : "undef");

ok 1, "Trace complete";