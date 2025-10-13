#!/usr/bin/env perl
# ABOUTME: Test script to check which grammar level handles arrow parsing
# ABOUTME: Tests whether NonBrace or regular Expr rules are used
use 5.42.0;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

# Test what level parses these
my @tests = (
    # These should all be BlockLevelExpression (NonBrace rules)
    ['$x->multiply($y->z)', 'Full statement with nested arrow'],
    ['$y->z', 'Simple arrow expression'],

    # Try to isolate where the problem is
    ['$x->multiply($y)', 'Arrow with simple param'],
    ['$x->foo()', 'Arrow with no params'],
);

foreach my $test (@tests) {
    my ($code, $desc) = @$test;
    print "\n" . "=" x 60 . "\n";
    print "Testing: $code\n";
    print "Description: $desc\n";
    print "=" x 60 . "\n";

    my $result = $parser->parse_string($code);

    if ($result) {
        print "PASS\n";
    } else {
        print "FAIL\n";
    }
}
