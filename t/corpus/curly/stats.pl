# Descriptive statistics of a data set: mean, median, mode, variance,
# standard deviation (with a square root by Newton's method, there being
# no sqrt yet), quartiles, a histogram, and a correlation.
use v5.42;

my @heights = (162, 175, 168, 181, 159, 172, 177, 165, 170, 188, 174, 169, 163, 179, 171, 170, 166, 183, 176, 170);
my @weights = (55, 74, 63, 82, 52, 70, 77, 60, 68, 90, 72, 66, 57, 80, 69, 71, 61, 85, 75, 67);

sub sum (@x) { my $s = 0; $s += $_ for @x; return $s }
sub mean (@x) { sum(@x) / @x }

sub median (@x) {
    my @s = sort { $a <=> $b } @x;
    my $n = @s;
    return $n % 2 ? $s[($n - 1) / 2] : ($s[$n / 2 - 1] + $s[$n / 2]) / 2;
}

sub mode (@x) {
    my %c;
    $c{$_}++ for @x;
    my ($best) = sort { $c{$b} <=> $c{$a} || $a <=> $b } keys %c;
    return ($best, $c{$best});
}

sub square_root ($x) {
    die "no square root of $x\n" if $x < 0;
    return 0 if $x == 0;
    my $g = $x;
    for (1 .. 60) {
        my $next = ($g + $x / $g) / 2;
        last if $next == $g;
        $g = $next;
    }
    return $g;
}

sub variance (@x) {
    my $m = mean(@x);
    return sum(map { ($_ - $m) ** 2 } @x) / (@x - 1);
}

sub quartiles (@x) {
    my @s = sort { $a <=> $b } @x;
    my $half = (@s - @s % 2) / 2;
    return (median(@s[0 .. $half - 1]), median(@s), median(@s[-$half .. -1]));
}

sub correlation ($x, $y) {
    my ($mx, $my) = (mean($x->@*), mean($y->@*));
    my ($sxy, $sxx, $syy) = (0, 0, 0);
    for my $i (0 .. $x->$#*) {
        $sxy += ($x->[$i] - $mx) * ($y->[$i] - $my);
        $sxx += ($x->[$i] - $mx) ** 2;
        $syy += ($y->[$i] - $my) ** 2;
    }
    return $sxy / square_root($sxx * $syy);
}

printf "n        %d\n", scalar(@heights);
printf "mean     %.2f\n", mean(@heights);
printf "median   %s\n", median(@heights);
printf "mode     %d (%d times)\n", mode(@heights);
printf "variance %.3f\n", variance(@heights);
printf "std dev  %.3f\n", square_root(variance(@heights));
printf "quartiles %s %s %s\n", quartiles(@heights);
printf "range    %d to %d\n", (sort { $a <=> $b } @heights)[0, -1];

for my $x (2, 10, 144, 1e6, 0.25) {
    printf "sqrt(%s) = %.10f\n", $x, square_root($x);
}

my %bins;
$bins{ $_ - $_ % 5 }++ for @heights;
for my $bin (sort { $a <=> $b } keys %bins) {
    printf "%3d-%3d %s\n", $bin, $bin + 4, "*" x $bins{$bin};
}
printf "height and weight correlate at %.4f\n", correlation(\@heights, \@weights);
