#!/usr/bin/env perl
# ABOUTME: Absolute minimal test case for arrow-in-parameter issue
# ABOUTME: Strip down to the simplest possible failing case
use 5.42.0;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

# Most minimal cases
my @tests = (
    ['$a->b($c)',       'Arrow, var param - PASS'],
    ['$a->b($c->d)',    'Arrow, arrow param - FAIL'],
    ['$a->b(($c->d))',  'Double parens - works'],
    ['$a->b($c->d,)',   'Trailing comma - works'],
);

foreach my $test (@tests) {
    my ($code, $desc) = @$test;
    my $result = $parser->parse_string($code);
    printf "%-20s %-30s %s\n", $code, $desc, $result ? 'PASS' : 'FAIL';
}

# Let's also test if the issue is specific to closing paren
print "\n=== Other terminators ===\n";
my @terminator_tests = (
    ['$a->b($c->d]',    'Square bracket terminator'],
    ['$a->b($c->d}',    'Curly brace terminator'],
);

foreach my $test (@terminator_tests) {
    my ($code, $desc) = @$test;
    my $result = $parser->parse_string($code);
    printf "%-20s %-30s %s\n", $code, $desc, $result ? 'PASS' : 'FAIL';
}
