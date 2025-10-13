#!/usr/bin/env perl
# ABOUTME: Test if Expression can parse arrow chains in parentheses
# ABOUTME: Isolates whether the issue is with Expression itself
use 5.42.0;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

# Test Expression in various contexts
my @tests = (
    # Direct expressions
    ['$y->z',           'Direct arrow'],
    ['($y->z)',         'Parened arrow'],

    # In parameter lists
    ['f($y->z)',        'Function param'],
    ['f(($y->z))',      'Function double-paren'],

    # Nested arrow contexts
    ['$x->f($y->z)',    'Arrow param (FAILS)'],
    ['$x->f(($y->z))',  'Arrow double-paren'],

    # Array/hash refs with arrows
    ['[$y->z]',         'Array ref with arrow'],
    ['{a => $y->z}',    'Hash ref with arrow'],
);

foreach my $test (@tests) {
    my ($code, $desc) = @$test;
    my $result = $parser->parse_string($code);
    printf "%-25s %-30s %s\n", $code, $desc, $result ? 'PASS' : 'FAIL';
}
