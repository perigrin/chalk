# Fibonacci, from Opal's tests/002-fib.test.ts (stevan/pp), with the
# memoised and iterative versions a Perl programmer would compare it to.
use v5.42;

sub fib ($n) {
    if ($n < 2) {
        return $n;
    }
    return fib($n - 1) + fib($n - 2);
}

my %memo;
my $calls = 0;
sub fib_memo ($n) {
    $calls++;
    return $memo{$n} if exists $memo{$n};
    my $v = $n < 2 ? $n : fib_memo($n - 1) + fib_memo($n - 2);
    $memo{$n} = $v;
    return $v;
}

sub fib_iter ($n) {
    my ($x, $y) = (0, 1);
    for (1 .. $n) {
        ($x, $y) = ($y, $x + $y);
    }
    return $x;
}

say fib(20);
say join(" ", map { fib($_) } 0 .. 15);

for my $n (10, 30, 50, 90) {
    my $m = fib_memo($n);
    my $i = fib_iter($n);
    say "fib($n) = $m", $m == $i ? "" : " (iterative says $i)";
}
say "fib_memo was called $calls times; the memo holds ", scalar(keys %memo), " values";

# The first Fibonacci number with 15 digits
my ($k, $f) = (0, 0);
until (length($f) >= 15) {
    $k++;
    $f = fib_iter($k);
}
say "fib($k) = $f is the first with 15 digits";

# Every third is even
my @even = grep { $_ % 2 == 0 } map { fib_iter($_) } 1 .. 30;
say "even: @even[0 .. 4] ... ", scalar(@even), " of them";
