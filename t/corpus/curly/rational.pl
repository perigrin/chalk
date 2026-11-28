# Rational numbers as pairs in array references, always in lowest terms:
# arithmetic, comparison, continued fractions, and the harmonic numbers
# and an approximation of e done exactly.
use v5.42;

sub gcd ($x, $y) {
    ($x, $y) = ($y, $x % $y) while $y;
    return $x < 0 ? -$x : $x;
}

sub rat ($n, $d = 1) {
    die "zero denominator\n" if $d == 0;
    ($n, $d) = (-$n, -$d) if $d < 0;
    my $g = gcd($n, $d) || 1;
    return [$n / $g, $d / $g];
}

sub add ($x, $y) { rat($x->[0] * $y->[1] + $y->[0] * $x->[1], $x->[1] * $y->[1]) }
sub sub_ ($x, $y) { rat($x->[0] * $y->[1] - $y->[0] * $x->[1], $x->[1] * $y->[1]) }
sub mul ($x, $y) { rat($x->[0] * $y->[0], $x->[1] * $y->[1]) }
sub div ($x, $y) { rat($x->[0] * $y->[1], $x->[1] * $y->[0]) }
sub cmp_ ($x, $y) { $x->[0] * $y->[1] <=> $y->[0] * $x->[1] }
sub str ($x) { $x->[1] == 1 ? "$x->[0]" : "$x->[0]/$x->[1]" }

sub continued ($x) {
    my ($n, $d) = $x->@*;
    my @terms;
    while ($d) {
        my $q = ($n - $n % $d) / $d;
        push @terms, $q;
        ($n, $d) = ($d, $n - $q * $d);
    }
    return @terms;
}

my ($half, $third) = (rat(1, 2), rat(1, 3));
say str($half), " + ", str($third), " = ", str(add($half, $third));
say str($half), " - ", str($third), " = ", str(sub_($half, $third));
say str($half), " * ", str($third), " = ", str(mul($half, $third));
say str($half), " / ", str($third), " = ", str(div($half, $third));
say "6/-8 is ", str(rat(6, -8)), "; 0/5 is ", str(rat(0, 5));

my @fracs = map { rat($_->@*) } [3, 4], [2, 3], [5, 8], [7, 12], [1, 2], [-1, 3];
say "sorted: ", join(" ", map { str($_) } sort { cmp_($a, $b) } @fracs);

my $h = rat(0);
for my $n (1 .. 20) {
    $h = add($h, rat(1, $n));
    say "H($n) = ", str($h) if $n <= 5 || $n == 10 || $n == 20;
}

my ($e, $term) = (rat(1), rat(1));
for my $k (1 .. 12) {
    $term = div($term, rat($k));
    $e = add($e, $term);
}
say "e is about ", str($e), " = ", sprintf("%.15f", $e->[0] / $e->[1]);
say "continued fraction of 415/93: [", join(", ", continued(rat(415, 93))), "]";
say "continued fraction of that e: [", join(", ", continued($e)), "]";

try { rat(1, 0) } catch ($err) { print "rat(1, 0): $err" }
