# Greatest common divisor, from Opal's tests/003-gcd.test.ts (stevan/pp),
# with the least common multiple, Euclid's steps shown, and the
# extended algorithm.
use v5.42;

sub gcd ($a1, $b1) {
    if ($b1 == 0) {
        return $a1;
    }
    return gcd($b1, $a1 % $b1);
}

sub lcm ($x, $y) {
    return $x / gcd($x, $y) * $y;
}

sub euclid_steps ($x, $y) {
    my @steps;
    while ($y != 0) {
        my $r = $x % $y;
        push @steps, "$x = " . ($x - $r) / $y . " * $y + $r";
        ($x, $y) = ($y, $r);
    }
    return @steps;
}

# Returns (g, s, t) with s*x + t*y == g
sub extended ($x, $y) {
    return ($x, 1, 0) if $y == 0;
    my ($g, $s, $t) = extended($y, $x % $y);
    my $q = ($x - $x % $y) / $y;
    return ($g, $t, $s - $q * $t);
}

say gcd(48, 18);
for my $pair ([12, 8], [17, 5], [100, 75], [1071, 462], [270, 192]) {
    my ($x, $y) = $pair->@*;
    printf("gcd(%4d, %4d) = %3d   lcm = %6d\n", $x, $y, gcd($x, $y), lcm($x, $y));
}

say "Euclid on 1071 and 462:";
say "  $_" for euclid_steps(1071, 462);

my ($g, $s, $t) = extended(240, 46);
say "240*$s + 46*$t = $g";
die "wrong\n" unless 240 * $s + 46 * $t == $g;

my $all = 0;
$all = gcd($all, $_) for 84, 126, 210, 462;
say "gcd of 84, 126, 210, 462 is $all";

my $l = 1;
$l = lcm($l, $_) for 1 .. 20;
say "lcm of 1 .. 20 is $l";
