#!/usr/bin/env perl
# ABOUTME: Test arrow chain termination with different following tokens
# ABOUTME: Verify that comma helps ArrowChain know when to terminate
use 5.42.0;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

# What tokens can successfully follow an arrow chain?
my @tests = (
    # These all work - they clearly terminate the arrow
    ['$x->f($y->z,)',       'Followed by comma-paren'],
    ['$x->f($y->z;)',       'Followed by semicolon-paren (invalid perl)'],
    ['$x->f($y->z + 1)',    'Followed by operator'],

    # This fails - paren alone doesn't terminate
    ['$x->f($y->z)',        'Followed by paren only'],

    # What about other postfix operations after the arrow?
    ['$x->f($y->z[0])',     'Arrow then subscript'],
    ['$x->f($y->z{a})',     'Arrow then hash subscript'],
);

foreach my $test (@tests) {
    my ($code, $desc) = @$test;
    my $result = $parser->parse_string($code);
    printf "%-25s %-40s %s\n", $code, $desc, $result ? 'PASS' : 'FAIL';
}
