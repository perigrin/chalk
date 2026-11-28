# Arithmetic on numbers too large for 64 bits, held as strings of
# digits: addition, multiplication and comparison by hand, then 50!,
# 2**200 and the 300th Fibonacci number.
use v5.42;

sub big_add ($x, $y) {
    my ($i, $j, $carry, $out) = (length($x) - 1, length($y) - 1, 0, "");
    while ($i >= 0 || $j >= 0 || $carry) {
        my $sum = $carry;
        $sum += substr($x, $i--, 1) if $i >= 0;
        $sum += substr($y, $j--, 1) if $j >= 0;
        $out = ($sum % 10) . $out;
        $carry = $sum >= 10 ? 1 : 0;
    }
    return $out;
}

sub big_mul_small ($x, $k) {
    return "0" if $k == 0;
    my ($carry, $out) = (0, "");
    for (my $i = length($x) - 1; $i >= 0; $i--) {
        my $p = substr($x, $i, 1) * $k + $carry;
        $out = ($p % 10) . $out;
        $carry = ($p - $p % 10) / 10;
    }
    return ($carry ? $carry : "") . $out;
}

sub big_mul ($x, $y) {
    my $total = "0";
    my $shift = "";
    for (my $j = length($y) - 1; $j >= 0; $j--) {
        $total = big_add($total, big_mul_small($x, substr($y, $j, 1)) . $shift);
        $shift .= "0";
    }
    $total = substr($total, 1) while length($total) > 1 && substr($total, 0, 1) eq "0";
    return $total;
}

sub big_cmp ($x, $y) {
    return length($x) <=> length($y) || $x cmp $y;
}

sub group ($n) {
    my @g;
    while (length $n > 3) {
        unshift @g, substr($n, -3);
        $n = substr($n, 0, length($n) - 3);
    }
    unshift @g, $n;
    return join(",", @g);
}

my $f = "1";
$f = big_mul_small($f, $_) for 2 .. 50;
say "50! = $f";
my @zeros = grep { substr($f, $_, 1) eq "0" } 0 .. length($f) - 1;
say "    (", length($f), " digits, ", scalar(@zeros), " of them zeros)";

my $p = "1";
$p = big_mul_small($p, 2) for 1 .. 200;
say "2**200 = ", group($p);

my ($a1, $b1) = ("0", "1");
($a1, $b1) = ($b1, big_add($a1, $b1)) for 1 .. 300;
say "fib(300) = $a1";

say "12345678901234567890 * 98765432109876543210 = ", big_mul("12345678901234567890", "98765432109876543210");
say "check against 64 bits: ", big_mul("4294967296", "2147483647"), " = ", 4294967296 * 2147483647;
my @sorted = sort { big_cmp($a, $b) } ("100", "99", "1000000000000000000000", "999999999999999999999", "5");
say "sorted: @sorted";
