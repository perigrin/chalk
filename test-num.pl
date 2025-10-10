#!/usr/bin/env perl
# Test file with lots of numeric operations to reproduce the timeout issue

# Various numeric literals
my $int = 42;
my $neg = -42;
my $float = 3.14;
my $exp = 1e10;
my $neg_exp = -1e10;
my $small_exp = 1.23e-5;

# Numeric operations
my $add = $int + $float;
my $sub = $int - $float;
my $mul = $int * $float;
my $div = $int / $float;
my $mod = $int % 10;
my $pow = $int ** 2;

# Complex expressions
my $complex1 = ($int + $float) * ($exp - $neg_exp) / ($small_exp + 1);
my $complex2 = $int + $float * $exp - $neg_exp / $small_exp + 1;
my $complex3 = $int * $float + $exp / $neg_exp - $small_exp * 1;

# Comparisons
my $eq = $int == 42;
my $ne = $int != 0;
my $lt = $int < 100;
my $gt = $int > 0;
my $le = $int <= 42;
my $ge = $int >= 42;

# Bitwise operations
my $and = $int & 0xFF;
my $or = $int | 0x100;
my $xor = $int ^ 0x0F;
my $not = ~$int;
my $lshift = $int << 2;
my $rshift = $int >> 2;

# Multiple operations in one expression
my $chain = 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10;
my $nested = ((1 + 2) * (3 + 4)) / ((5 + 6) - (7 + 8));

# Different numeric formats
my $hex = 0xFF;
my $oct = 0755;
my $bin = 0b1010;

print "All numeric tests done\n";