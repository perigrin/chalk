#!/usr/bin/env perl
# Test with highly ambiguous numeric expressions that could cause exponential parsing

# Ambiguous precedence chains that require extensive backtracking
my $x = 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10 +
        11 + 12 + 13 + 14 + 15 + 16 + 17 + 18 + 19 + 20 +
        21 + 22 + 23 + 24 + 25 + 26 + 27 + 28 + 29 + 30 +
        31 + 32 + 33 + 34 + 35 + 36 + 37 + 38 + 39 + 40;

# Deeply nested with multiple operators creating ambiguity
my $y = 1 + 2 * 3 + 4 * 5 + 6 * 7 + 8 * 9 + 10 * 11 + 12 * 13 + 14 * 15 +
        16 * 17 + 18 * 19 + 20 * 21 + 22 * 23 + 24 * 25 + 26 * 27 + 28 * 29 +
        30 * 31 + 32 * 33 + 34 * 35 + 36 * 37 + 38 * 39 + 40 * 41 + 42 * 43;

# Exponential expressions that might create multiple parse paths
my $e = 1e1 + 2e2 + 3e3 + 4e4 + 5e5 + 6e6 + 7e7 + 8e8 + 9e9 +
        1e-1 + 2e-2 + 3e-3 + 4e-4 + 5e-5 + 6e-6 + 7e-7 + 8e-8 + 9e-9;

# Multiple levels of precedence
my $p = 1 ** 2 ** 3 + 4 ** 5 ** 6 + 7 ** 8 ** 9;

print "Test done\n";