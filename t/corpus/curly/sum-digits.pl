# Sum of digits, from Opal's author/TESTING.md (stevan/pp). Opal's
# version divides with int($n / 10); there is no int yet, so the digit
# is taken off before dividing, which leaves a whole quotient (BENDS.md).
use v5.42;

sub sum_digits ($n) {
    return 0 if $n == 0;
    return ($n % 10) + sum_digits(($n - $n % 10) / 10);
}

sub digital_root ($n) {
    while ($n >= 10) {
        $n = sum_digits($n);
    }
    return $n;
}

sub digits_by_string ($n) {
    my $sum = 0;
    $sum += $_ for split_chars("$n");
    return $sum;
}

sub split_chars ($s) {
    return map { substr($s, $_, 1) } 0 .. length($s) - 1;
}

for my $n (0, 7, 42, 1234, 99999, 2026, 9876543210) {
    my $s = sum_digits($n);
    die "the two ways differ at $n\n" unless $s == digits_by_string($n);
    printf("%10d  sum %2d  root %d\n", $n, $s, digital_root($n));
}

# Harshad numbers: divisible by the sum of their digits
my @harshad = grep { $_ % sum_digits($_) == 0 } 1 .. 60;
say "Harshad numbers to 60: @harshad";

# How many numbers below 1000 have each digit sum
my %count;
$count{sum_digits($_)}++ for 0 .. 999;
my @common = sort { $count{$b} <=> $count{$a} || $a <=> $b } keys %count;
say "commonest digit sums below 1000: ", join(", ", map { "$_ ($count{$_})" } @common[0 .. 3]);
say "digit sum 27 happens ", $count{27}, " time", ($count{27} == 1 ? "" : "s");
