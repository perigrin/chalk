#!/usr/bin/env perl
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use lib 'lib';
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::ChalkSyntax;

# Test that "return" keyword is rejected when parsed as identifier
my $code = 'return -42';

my $grammar = Chalk::Grammar->new();
$grammar->load_from_file('grammar/chalk.bnf');

my $chalksyntax = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);
my $parser = Chalk::Parser->new(
    grammar => $grammar,
    semiring => $chalksyntax
);

say "Testing: $code";
my $result = $parser->parse($code);

if ($result) {
    say "Parse succeeded";
    say "Result: ", $result->to_string;
} else {
    say "Parse failed (expected - return as identifier should be rejected)";
}
