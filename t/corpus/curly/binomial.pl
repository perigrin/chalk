# Binomial coefficients, from Opal's author/TESTING.md (stevan/pp): the
# recursive definition, Pascal's triangle built row by row, and the
# multiplicative formula, each checked against the others.
use v5.42;

sub binomial ($n, $k) {
    return 1 if $k == 0 || $k == $n;
    return binomial($n-1, $k-1) + binomial($n-1, $k);
}

sub pascal ($rows) {
    my @tri = ([1]);
    for my $r (1 .. $rows - 1) {
        my $prev = $tri[$r - 1];
        my @row = (1);
        for my $i (1 .. $r - 1) {
            push @row, $prev->[$i - 1] + $prev->[$i];
        }
        push @row, 1;
        push @tri, \@row;
    }
    return \@tri;
}

sub choose ($n, $k) {
    $k = $n - $k if $k > $n - $k;
    my $c = 1;
    for my $i (1 .. $k) {
        $c = $c * ($n - $k + $i) / $i;
    }
    return $c;
}

say binomial(10, 4);

my $tri = pascal(12);
my $width = length(join(" ", $tri->[-1]->@*));
for my $row ($tri->@*) {
    my $line = join(" ", $row->@*);
    my $pad = ($width - length($line)) / 2;
    say " " x $pad, $line;
}

my $bad = 0;
for my $n (0 .. 11) {
    for my $k (0 .. $n) {
        my @v = (binomial($n, $k), $tri->[$n][$k], choose($n, $k));
        $bad++ unless $v[0] == $v[1] && $v[1] == $v[2];
    }
}
say "disagreements: $bad";

my $sum = 0;
$sum += $_ for $tri->[11]->@*;
say "row 11 sums to $sum = 2**11";
say "C(30, 15) = ", choose(30, 15);
say "C(52, 5) = ", choose(52, 5), " poker hands";
