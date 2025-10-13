#!/usr/bin/env perl
# ABOUTME: Trace parsing to understand why $x->multiply($y->z) fails
# ABOUTME: Tests minimal variations to isolate the grammar issue
use 5.42.0;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

# Minimal test cases to isolate the issue
my @tests = (
    # What we know works
    ['$y->z',                   'Simple arrow chain'],
    ['$x->multiply($y)',        'Arrow with variable param'],
    ['multiply($y->z)',         'Function with arrow param'],
    ['$x->multiply(($y->z))',   'Arrow with parened arrow param'],

    # The failing case
    ['$x->multiply($y->z)',     'Arrow with arrow param (FAILS)'],

    # Let's test if it's specific to method names
    ['$x->m($y->z)',            'Short method name'],
    ['$x->a($y->b)',            'Single char methods'],

    # Test with literals instead of arrows
    ['$x->multiply(1)',         'Arrow with literal'],
    ['$x->multiply($y + 1)',    'Arrow with expression'],
);

foreach my $test (@tests) {
    my ($code, $desc) = @$test;
    my $result = $parser->parse_string($code);
    printf "%-30s %-40s %s\n", $code, $desc, $result ? 'PASS' : 'FAIL';
}
