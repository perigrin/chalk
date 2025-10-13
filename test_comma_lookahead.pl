#!/usr/bin/env perl
# ABOUTME: Test if comma provides necessary lookahead for arrow expressions
# ABOUTME: Investigate why $x->f($y->z, 1) passes but $x->f($y->z) fails
use 5.42.0;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

# Test comma variations
my @tests = (
    # Comma after arrow - these should work
    ['$x->f($y->z,)',       'Trailing comma'],
    ['$x->f($y->z, )',      'Trailing comma with space'],

    # Arrow variations
    ['$x->f($y->z)',        'No comma - FAILS'],
    ['$x->f($y->z, 1)',     'Comma then literal - PASSES'],
    ['$x->f($y->z, $a)',    'Comma then var'],

    # What about semicolons or other terminators?
    ['$x->f($y->z);',       'Semicolon after'],
);

foreach my $test (@tests) {
    my ($code, $desc) = @$test;
    my $result = $parser->parse_string($code);
    printf "%-25s %-30s %s\n", $code, $desc, $result ? 'PASS' : 'FAIL';
}
