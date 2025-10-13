#!/usr/bin/env perl
use 5.42.0;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

# Test 1: Simple multi-line string in isolation
my $code1 = q{eval 'while (0) {
    print "foo\n";
}
/^/ && (print "ok 5\n");
';};

say "Test 1: Multi-line eval string";
my $result1 = $parser->parse_string($code1);
say $result1 ? "SUCCESS" : "FAILED";
say "-" x 60;

# Test 2: Just the string literal
my $code2 = q{'while (0) {
    print "foo\n";
}
/^/ && (print "ok 5\n");
'};

say "Test 2: Just the string literal";
my $result2 = $parser->parse_string($code2);
say $result2 ? "SUCCESS" : "FAILED";
say "-" x 60;

# Test 3: Simple single-line string
my $code3 = q{my $x = 'hello world';};
say "Test 3: Simple single-line string";
my $result3 = $parser->parse_string($code3);
say $result3 ? "SUCCESS" : "FAILED";
