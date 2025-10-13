#!/usr/bin/env perl
# ABOUTME: Test exact lines 1-22 from lex.t to debug parsing failure
# ABOUTME: Determine what's different about full file vs isolated tests
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

print "Testing exact lex.t lines 1-22\n";
print "=" x 60 . "\n\n";

local $SIG{__WARN__} = sub {};

# Lines 1-21 (should work according to debug_lex_progress.pl)
my $lines_1_21 = q{#!./perl

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

};

print "Test 1: Lines 1-21\n";
my $r1 = $parser->parse_string($lines_1_21);
printf "  Result: %s\n\n", $r1 ? "PASS ✓" : "FAIL ✗";

# Lines 1-22 (this should fail according to debug_lex_progress.pl)
my $lines_1_22 = q{#!./perl

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
};

print "Test 2: Lines 1-22 (adding line 22)\n";
my $r2 = $parser->parse_string($lines_1_22);
printf "  Result: %s\n\n", $r2 ? "PASS ✓" : "FAIL ✗";

print "=" x 60 . "\n";
if ($r1 && !$r2) {
    print "✓ Lines 1-21 parse\n";
    print "✗ Line 22 breaks parsing\n";
    print "\nLine 22 is: eval 'while (0) {\n";
    print "This is an INCOMPLETE eval STRING.\n";
} elsif ($r1 && $r2) {
    print "Both parse! The issue must be later in the file.\n";
} else {
    print "Lines 1-21 already fail.\n";
}
