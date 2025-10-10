#!/usr/bin/env perl
# Complex numeric expressions that might cause exponential parsing

# Very deeply nested arithmetic expressions
my $deep = ((((((((((1 + 2) * 3) - 4) / 5) + 6) * 7) - 8) / 9) + 10) * 11);

# Multiple chained operations that could cause backtracking
my $chain1 = 1 + 2 * 3 - 4 / 5 + 6 * 7 - 8 / 9 + 10 * 11 - 12 / 13 + 14 * 15;
my $chain2 = 1 * 2 + 3 * 4 - 5 * 6 + 7 * 8 - 9 * 10 + 11 * 12 - 13 * 14 + 15;
my $chain3 = 1 / 2 + 3 / 4 + 5 / 6 + 7 / 8 + 9 / 10 + 11 / 12 + 13 / 14 + 15;

# Exponential notation with operations
my $exp1 = 1e10 + 2e10 - 3e10 * 4e10 / 5e10;
my $exp2 = 1.23e-5 + 4.56e-6 * 7.89e-7 - 1.11e-8 / 2.22e-9;
my $exp3 = -1e10 * -2e10 / -3e10 + -4e10 - -5e10;

# Mixed precedence that might cause issues
my $mixed1 = 1 + 2 * 3 ** 4 - 5 / 6 + 7 % 8 * 9 - 10;
my $mixed2 = 1 ** 2 + 3 ** 4 * 5 ** 6 - 7 ** 8 / 9 ** 10;
my $mixed3 = 1 << 2 + 3 >> 4 * 5 & 6 | 7 ^ 8 + 9 - 10;

# Ternary with numeric expressions
my $tern1 = 1 + 2 > 3 * 4 ? 5 - 6 : 7 / 8;
my $tern2 = (1 + 2) * (3 + 4) > (5 + 6) * (7 + 8) ? (9 + 10) / (11 + 12) : (13 + 14) * (15 + 16);

# Very long expression on single line
my $long = 1 + 2 - 3 * 4 / 5 + 6 - 7 * 8 / 9 + 10 - 11 * 12 / 13 + 14 - 15 * 16 / 17 + 18 - 19 * 20 / 21 + 22 - 23 * 24 / 25 + 26 - 27 * 28 / 29 + 30;

print "Done\n";