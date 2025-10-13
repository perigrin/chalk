#!/usr/bin/env perl
# ABOUTME: Test parsing of $#array (array length) syntax
# ABOUTME: Also test $#$ref (array length of dereferenced scalar)
use 5.42.0;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

my @tests = (
    # Basic array length
    ['$#array',              'Array length variable'],
    ['$#output_lines',       'Array length (from Heredoc.pm)'],

    # Array length of dereference
    ['$#$ref',               'Array length of dereferenced scalar'],
    ['$#$existing_children', 'Array length dereference (from SPPF.pm)'],

    # In expressions
    ['0..$#array',           'Range with array length'],
    ['0..$#output_lines',    'Range with array length (actual usage)'],

    # With subscripts
    ['$array[$#array]',      'Last element access'],
);

foreach my $test (@tests) {
    my ($code, $desc) = @$test;
    my $result = $parser->parse_string($code);
    printf "%-30s %-45s %s\n", $code, $desc, $result ? 'PASS' : 'FAIL';
}
