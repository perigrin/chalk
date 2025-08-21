#!/usr/bin/env perl
# ABOUTME: Debug test to understand parser behavior
# ABOUTME: Traces through simple parse to identify issues
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

# Simple test case
my $grammar = Grammar->build_grammar(
    [ 'S' => ['a'] ],
);

say "Grammar rules:";
for my $rule ($grammar->rules_for('S')) {
    say "  Rule: $rule";
}

my $parser = Parser->new(grammar => $grammar);
say "Parser created";

# Test on empty input to see if epsilon works
my $result = $parser->parse();
say "Empty parse result: " . (defined $result ? ref($result) . " - $result" : "undef");

# Test on single 'a'
$result = $parser->parse(qw(a));
say "Parse result for 'a': " . (defined $result ? ref($result) . " - $result" : "undef");

ok 1, "Debug complete";