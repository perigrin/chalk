#!/usr/bin/env perl
# ABOUTME: Debug parentheses parsing specifically
# ABOUTME: Tests why parentheses fail in arithmetic grammar
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

say "Grammar rules:";
for my $nt (sort keys $grammar->rules->%*) {
    for my $rule ($grammar->rules_for($nt)) {
        say "  $rule";
    }
}

my $parser = Parser->new(grammar => $grammar);

# Test that works
my $result = $parser->parse(qw(num + num));
say "num + num: " . (defined $result ? "SUCCESS - $result" : "FAIL");

# Test simple parentheses  
$result = $parser->parse(qw/( num )/);
say "( num ): " . (defined $result ? "SUCCESS - $result" : "FAIL");

# Test the failing case
$result = $parser->parse(qw/( num + num )/);
say "( num + num ): " . (defined $result ? "SUCCESS - $result" : "FAIL");

ok 1, "Debug complete";