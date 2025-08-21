#!/usr/bin/env perl
# ABOUTME: Debug simplest parentheses case
# ABOUTME: Tests F -> ( E ) with E -> num to isolate the issue
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

# Simplest possible parentheses grammar
my $grammar = Grammar->build_grammar(
    [ 'F' => [qw/( E )/] ],
    [ 'E' => ['num'] ],
);

say "Simple grammar rules:";
for my $nt (sort keys $grammar->rules->%*) {
    for my $rule ($grammar->rules_for($nt)) {
        say "  $rule";
    }
}

my $parser = Parser->new(grammar => $grammar);

# Test the simplest case
my $result = $parser->parse(qw/( num )/);
say "( num ): " . (defined $result ? "SUCCESS - $result" : "FAIL");

# Also test without parentheses to ensure E -> num works
$grammar = Grammar->build_grammar(
    [ 'E' => ['num'] ],
);
$parser = Parser->new(grammar => $grammar);
$result = $parser->parse(qw/num/);
say "num: " . (defined $result ? "SUCCESS - $result" : "FAIL");

ok 1, "Debug complete";