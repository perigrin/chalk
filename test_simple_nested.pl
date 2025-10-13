#!/usr/bin/env perl
# ABOUTME: Test progressively simpler nested arrow cases
# ABOUTME: Find the minimal failing case
use 5.42.0;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

# Progressive simplification
my @tests = (
    # Start with what we know
    ['f($y->z)',         'Function - PASS'],
    ['$x->f($y)',        'Arrow simple - PASS'],

    # The minimal failure
    ['$x->f($y->z)',     'Arrow nested - FAIL'],

    # Even simpler
    ['$a->b($c->d)',     'Single chars'],

    # What if we use different variables?
    ['$x->f($z->w)',     'Different vars'],

    # What if the inner arrow has no call?
    ['$x->f($y->z, 1)',  'Arrow first param'],
    ['$x->f(1, $y->z)',  'Arrow second param'],
);

foreach my $test (@tests) {
    my ($code, $desc) = @$test;
    my $result = $parser->parse_string($code);
    printf "%-20s %-25s %s\n", $code, $desc, $result ? 'PASS' : 'FAIL';
}
