# Factorial three ways, from Opal's tests/001-fact.test.ts (stevan/pp),
# grown into a table.
use v5.42;

sub fact ($n) {
    if ($n == 0) {
        return 1;
    } else {
        return $n * fact( $n - 1 );
    }
}

sub fact_loop ($n) {
    my $acc = 1;
    for my $i (2 .. $n) {
        $acc *= $i;
    }
    return $acc;
}

sub fact_tail ($n, $acc = 1) {
    return $acc if $n <= 1;
    return fact_tail($n - 1, $acc * $n);
}

say(fact(10));

printf("%3s %20s\n", "n", "n!");
for my $n (0 .. 20) {
    my @three = (fact($n), fact_loop($n), fact_tail($n));
    die "disagree at $n: @three\n" unless $three[0] == $three[1] && $three[1] == $three[2];
    printf("%3d %20d\n", $n, $three[0]);
}

my $digits = length(fact(20));
say "20! has $digits digits";
my $sum = 0;
$sum += $_ for split_digits(fact(20));
say "and their sum is $sum";

sub split_digits ($n) {
    my @d;
    my $s = "$n";
    for my $i (0 .. length($s) - 1) {
        push @d, substr($s, $i, 1);
    }
    return @d;
}
