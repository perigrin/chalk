#!/usr/bin/env perl
use 5.42.0;

# Test the QuotedString regex pattern
my $pattern = qr/'(?:[^'\\]|\\.)*'/;

# Test 1: Single-line string
my $test1 = q{'hello world'};
if ($test1 =~ /^$pattern$/) {
    say "Test 1 PASS: Single-line string matched";
} else {
    say "Test 1 FAIL: Single-line string did NOT match";
}

# Test 2: Multi-line string
my $test2 = q{'while (0) {
    print "foo\n";
}
/^/ && (print "ok 5\n");
'};

say "\nTest 2 input:";
say $test2;
say "";

if ($test2 =~ /^$pattern$/s) {
    say "Test 2 PASS: Multi-line string matched with /s";
} else {
    say "Test 2 FAIL: Multi-line string did NOT match with /s";
}

if ($test2 =~ /^$pattern$/) {
    say "Test 2 PASS: Multi-line string matched without /s";
} else {
    say "Test 2 FAIL: Multi-line string did NOT match without /s";
}

# Test 3: Does [^'\\] match newlines?
my $test3 = "abc\ndef";
if ($test3 =~ /^[^x]+$/) {
    say "\nTest 3 PASS: [^x]+ matches newlines";
} else {
    say "\nTest 3 FAIL: [^x]+ does NOT match newlines";
}
