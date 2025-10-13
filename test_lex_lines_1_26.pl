#!/usr/bin/env perl
# ABOUTME: Test lines 1-26 from lex.t (complete eval statement)
# ABOUTME: Verify the eval STRING works when complete
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

print "Testing lex.t lines 1-26 (complete eval)\n";
print "=" x 60 . "\n\n";

local $SIG{__WARN__} = sub {};

# Lines 1-26 (complete through the eval statement)
my $lines_1_26 = q{#!./perl

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
';
};

print "Test: Lines 1-26 (complete eval statement)\n";
my $result = $parser->parse_string($lines_1_26);
printf "  Result: %s\n\n", $result ? "PASS ✓" : "FAIL ✗";

if ($result) {
    print "SUCCESS! The eval STRING support works!\n";
    print "The binary search failed because line 22 is mid-string.\n";
} else {
    print "FAILED. There's still an issue even with complete eval.\n";
}
