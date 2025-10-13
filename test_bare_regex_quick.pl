#!/usr/bin/env -S perl -I lib
# ABOUTME: Quick test for bare regex parsing
# ABOUTME: Tests different bare regex contexts
use 5.42.0;
use utf8;
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

my @tests = (
    ['/^/;',                  'Bare regex with semicolon'],
    ['/^/ && print "hi";',    'Bare regex in && expression'],
    ['$_ =~ /^/;',            'Explicit binding'],
    ['if (/^/) { }',          'Bare regex in if condition'],
    ['/^/',                   'Bare regex without semicolon'],
);

for my $test (@tests) {
    my ($code, $desc) = @$test;
    my $result = $parser->parse_string($code);
    printf "%-40s %s\n", $desc, $result ? "PASS ✓" : "FAIL ✗";
}
