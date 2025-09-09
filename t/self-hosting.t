#!/usr/bin/env perl
# ABOUTME: Test chalk parsing its own source code for true self-hosting
# ABOUTME: This is the ultimate test - can chalk parse itself?
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);

local $| = 1;

# Test chalk parsing itself via CLI - the ultimate self-hosting test
diag "Testing chalk self-hosting via CLI";
my $cli_output = `./chalk chalk 2>&1`;
my $cli_success = $cli_output =~ /Parse successful:/;

# Don't output the full parse tree since it's huge
if ($cli_success) {
    diag "✓ Parse successful - chalk can parse its own source code!";
} else {
    diag "CLI output: $cli_output";
}

ok $cli_success, "Chalk successfully parses its own source code - true self-hosting achieved!";

done_testing;