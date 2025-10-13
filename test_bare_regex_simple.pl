#!/usr/bin/env perl
# ABOUTME: Test bare regex parsing without version requirement
# ABOUTME: Quick diagnostic for lex.t issue
use utf8;
use lib 'lib';

# Skip version check by commenting it out in the grammar temporarily
BEGIN {
    $ENV{CHALK_SKIP_VERSION_CHECK} = 1;
}

use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

print "Testing bare regex patterns:\n";
print "=" x 60 . "\n";

my @tests = (
    ['/^/;',                  'Bare regex with semicolon'],
    ['/^/ && 1;',             'Bare regex in && expression'],
    ['$_ =~ /^/;',            'Explicit =~ binding'],
    ['if (/^/) { }',          'Bare regex in if condition'],
);

for my $test (@tests) {
    my ($code, $desc) = @$test;
    my $result = eval { $parser->parse_string($code) };
    printf "%-40s %s\n", $desc, $result ? "PASS ✓" : "FAIL ✗";
}
