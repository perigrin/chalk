# The Collatz sequence, from Opal's author/TESTING.md (stevan/pp): the
# recursive version printing 27's sequence, then the longest sequence
# under a limit, with the lengths memoised in a hash.
use v5.42;
no warnings 'recursion';

my $printed = 0;
sub collatz ($n) {
    print "$n\n" if $printed++ < 12;
    return if $n == 1;
    if ($n % 2 == 0) {
        collatz($n / 2);
    } else {
        collatz(3 * $n + 1);
    }
}

collatz(27);
say "... $printed numbers in all";

my %length = (1 => 1);
sub steps ($n) {
    return $length{$n} if exists $length{$n};
    my $next = $n % 2 == 0 ? $n / 2 : 3 * $n + 1;
    my $len = 1 + steps($next);
    $length{$n} = $len;
    return $len;
}

my ($best, $best_len) = (1, 1);
for my $n (1 .. 3000) {
    my $len = steps($n);
    if ($len > $best_len) {
        ($best, $best_len) = ($n, $len);
    }
}
say "under 3000 the longest is $best, with $best_len numbers";

my $peak = 0;
my $n = $best;
while ($n != 1) {
    $peak = $n if $n > $peak;
    $n = $n % 2 ? 3 * $n + 1 : $n / 2;
}
say "and it climbs as high as $peak";

my @firsts;
my %seen_len;
for my $k (1 .. 40) {
    my $len = steps($k);
    next if $seen_len{$len}++;
    push @firsts, "$k:$len";
}
say "first to reach each length: @firsts[0 .. 9]";
say scalar(keys %length), " lengths remembered";
