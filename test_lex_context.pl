#!/usr/bin/env perl
# ABOUTME: Test if context from earlier lines affects eval parsing
# ABOUTME: Compare isolated eval vs eval in full context
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

print "Testing context dependency\n";
print "=" x 60 . "\n\n";

# Test 1: Just the eval (this should work)
my $just_eval = q{eval 'while (0) {
    print "foo\n";
}
/^/ && (print "ok 5\n");
';};

print "Test 1: Just the eval statement\n";
local $SIG{__WARN__} = sub {};
my $r1 = $parser->parse_string($just_eval);
printf "  Result: %s\n\n", $r1 ? "PASS" : "FAIL";

# Test 2: Lines 1-26 from lex.t (through the eval)
my $with_context = q{#!./perl

print "1..129\n";

$x = 'x';

print "#1	:$x: eq :x:\n";
if ($x eq 'x') {print "ok 1\n";} else {print "not ok 1\n";}

$x = $#[0];

if ($x eq '') {print "ok 2\n";} else {print "not ok 2\n";}

$x = $#x;

if ($x eq '-1') {print "ok 3\n";} else {print "not ok 3\n";}

$x = '\\'; # ';

if (length($x) == 1) {print "ok 4\n";} else {print "not ok 4\n";}

eval 'while (0) {
    print "foo\n";
}
/^/ && (print "ok 5\n");
';};

print "Test 2: Lines 1-26 with full context\n";
my $r2 = $parser->parse_string($with_context);
printf "  Result: %s\n\n", $r2 ? "PASS" : "FAIL";

# Test 3: Just lines 18-26 (the comment line through eval)
my $partial_context = q{$x = '\\'; # ';

if (length($x) == 1) {print "ok 4\n";} else {print "not ok 4\n";}

eval 'while (0) {
    print "foo\n";
}
/^/ && (print "ok 5\n");
';};

print "Test 3: Lines 18-26 (partial context)\n";
my $r3 = $parser->parse_string($partial_context);
printf "  Result: %s\n\n", $r3 ? "PASS" : "FAIL";
