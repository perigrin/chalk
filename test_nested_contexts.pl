#!/usr/bin/env perl
# ABOUTME: Test if arrow-in-parameter issue is specific to certain contexts
# ABOUTME: Try arrows in array refs, hash refs, etc.
use 5.42.0;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

my @tests = (
    # Function calls
    ['f($c->d)',        'Function with arrow param - PASS'],

    # Arrow method calls
    ['$a->b($c->d)',    'Arrow with arrow param - FAIL'],

    # Array ref contexts
    ['[$c->d]',         'Array ref with arrow - PASS'],
    ['$a->b([$c->d])',  'Arrow with array-wrapped arrow'],

    # Hash ref contexts
    ['{a => $c->d}',    'Hash ref with arrow - PASS'],
    ['$a->b({a => $c->d})', 'Arrow with hash-wrapped arrow'],

    # Assignment contexts
    ['$x = $c->d',      'Assignment with arrow'],
    ['$a->b($x = $c->d)', 'Arrow with assignment expr'],
);

foreach my $test (@tests) {
    my ($code, $desc) = @$test;
    my $result = $parser->parse_string($code);
    printf "%-25s %-35s %s\n", $code, $desc, $result ? 'PASS' : 'FAIL';
}
