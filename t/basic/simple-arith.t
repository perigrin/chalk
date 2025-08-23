#!/usr/bin/env perl
# ABOUTME: Test simple arithmetic grammar
# ABOUTME: Focuses on basic arithmetic parsing to isolate issues
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

# Simple arithmetic
my $grammar = Grammar->build_grammar(
    [ 'E' => ['num'] ],
);

my $parser = Parser->new(grammar => $grammar);

my $result = $parser->parse_tokens(qw(num));
say "Single num result: " . (defined $result ? ref($result) . " - $result" : "undef");

ok $result, "Parse single num";

# Now try with addition
$grammar = Grammar->build_grammar(
    [ 'E' => [qw(E + E)] ],
    [ 'E' => ['num'] ],
);

$parser = Parser->new(grammar => $grammar);
$result = $parser->parse_tokens(qw(num + num));
say "Addition result: " . (defined $result ? ref($result) . " - $result" : "undef");

ok $result, "Parse num + num";