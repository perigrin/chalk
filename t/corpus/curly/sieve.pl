# The sieve of Eratosthenes, and what can be done with the primes it
# finds: twin primes, Goldbach's partitions, prime factors, and the gaps.
use v5.42;

sub sieve ($limit) {
    my @is_prime = (1) x ($limit + 1);
    @is_prime[0, 1] = (0, 0);
    for (my $i = 2; $i * $i <= $limit; $i++) {
        next unless $is_prime[$i];
        for (my $j = $i * $i; $j <= $limit; $j += $i) {
            $is_prime[$j] = 0;
        }
    }
    return grep { $is_prime[$_] } 0 .. $limit;
}

my @primes = sieve(1000);
say "There are ", scalar(@primes), " primes below 1000";
say "The first twenty: @primes[0 .. 19]";
say "The last five:    @primes[-5 .. -1]";

my %is_prime = map { ($_ => 1) } @primes;

my @twins;
for my $p (@primes) {
    push @twins, "($p, " . ($p + 2) . ")" if $is_prime{$p + 2};
}
say scalar(@twins), " twin pairs; the first six: ", join(" ", @twins[0 .. 5]);

for my $even (4, 28, 100, 998) {
    my @ways;
    for my $p (@primes) {
        last if $p > $even / 2;
        push @ways, "$p+" . ($even - $p) if $is_prime{$even - $p};
    }
    say "$even = ", join(" = ", @ways[0 .. ($#ways < 2 ? $#ways : 2)]), " (", scalar(@ways), " ways)";
}

sub factors ($n) {
    my @f;
    for my $p (@primes) {
        last if $p * $p > $n;
        while ($n % $p == 0) {
            push @f, $p;
            $n /= $p;
        }
    }
    push @f, $n if $n > 1;
    return @f;
}

for my $n (360, 997, 1001, 65536, 999999) {
    say "$n = ", join(" x ", factors($n));
}

my %gaps;
for my $i (1 .. $#primes) {
    $gaps{$primes[$i] - $primes[$i - 1]}++;
}
say "gaps: ", join(", ", map { "$_:$gaps{$_}" } sort { $a <=> $b } keys %gaps);
