# Dynamic programming over arrays: edit distance with its alignment, the
# 0/1 knapsack with the items chosen, coin change counted and minimised,
# and the longest increasing subsequence.
use v5.42;

sub min (@xs) {
    my $m = shift @xs;
    for (@xs) { $m = $_ if $_ < $m }
    return $m;
}

sub edit_distance ($s, $t) {
    my @d;
    $d[$_][0] = $_ for 0 .. length $s;
    $d[0][$_] = $_ for 0 .. length $t;
    for my $i (1 .. length $s) {
        for my $j (1 .. length $t) {
            my $cost = substr($s, $i - 1, 1) eq substr($t, $j - 1, 1) ? 0 : 1;
            $d[$i][$j] = min($d[$i - 1][$j] + 1, $d[$i][$j - 1] + 1, $d[$i - 1][$j - 1] + $cost);
        }
    }
    return $d[length $s][length $t];
}

sub knapsack ($cap, @items) {
    my @best = ([(0) x ($cap + 1)]);
    for my $i (1 .. @items) {
        my ($name, $w, $v) = @{ $items[$i - 1] };
        for my $c (0 .. $cap) {
            $best[$i][$c] = $best[$i - 1][$c];
            if ($w <= $c && $best[$i - 1][$c - $w] + $v > $best[$i][$c]) {
                $best[$i][$c] = $best[$i - 1][$c - $w] + $v;
            }
        }
    }
    my @chosen;
    my $c = $cap;
    for (my $i = @items; $i > 0; $i--) {
        if ($best[$i][$c] != $best[$i - 1][$c]) {
            unshift @chosen, $items[$i - 1][0];
            $c -= $items[$i - 1][1];
        }
    }
    return ($best[@items][$cap], @chosen);
}

sub coin_ways ($amount, @coins) {
    my @ways = (1, (0) x $amount);
    for my $coin (@coins) {
        $ways[$_] += $ways[$_ - $coin] for $coin .. $amount;
    }
    return $ways[$amount];
}

sub fewest_coins ($amount, @coins) {
    my @best = (0);
    my @last;
    for my $x (1 .. $amount) {
        for my $coin (@coins) {
            next if $coin > $x || !defined $best[$x - $coin];
            if (!defined $best[$x] || $best[$x - $coin] + 1 < $best[$x]) {
                $best[$x] = $best[$x - $coin] + 1;
                $last[$x] = $coin;
            }
        }
    }
    return () unless defined $best[$amount];
    my @used;
    for (my $x = $amount; $x > 0; $x -= $last[$x]) { push @used, $last[$x] }
    return @used;
}

sub lis (@a) {
    my (@len, @prev);
    for my $i (0 .. $#a) {
        ($len[$i], $prev[$i]) = (1, -1);
        for my $j (0 .. $i - 1) {
            ($len[$i], $prev[$i]) = ($len[$j] + 1, $j) if $a[$j] < $a[$i] && $len[$j] + 1 > $len[$i];
        }
    }
    my $end = 0;
    for my $i (0 .. $#a) { $end = $i if $len[$i] > $len[$end] }
    my @seq;
    for (my $i = $end; $i >= 0; $i = $prev[$i]) { unshift @seq, $a[$i] }
    return @seq;
}

for my $pair ([qw(kitten sitting)], [qw(flaw lawn)], [qw(intention execution)], ["", "abc"], [qw(same same)]) {
    say "edit distance $pair->[0] -> $pair->[1]: ", edit_distance($pair->@*);
}

my ($value, @chosen) = knapsack(10, [qw(map 9 150)], [qw(compass 13 35)], [qw(water 3 200)], [qw(sandwich 5 160)], [qw(glucose 2 60)], [qw(tin 1 45)], [qw(banana 4 60)]);
say "knapsack of 10: worth $value with @chosen";

say "ways to make 100 from 1 5 10 25 50: ", coin_ways(100, 1, 5, 10, 25, 50);
say "ways to make 200p from British coins: ", coin_ways(200, 1, 2, 5, 10, 20, 50, 100, 200);
for my $case ([63, 1, 5, 10, 21, 25], [30, 1, 15, 25], [7, 2, 4]) {
    my ($amount, @coins) = $case->@*;
    my @used = fewest_coins($amount, @coins);
    say "fewest coins for $amount from (@coins): ", @used ? "@used" : "impossible";
}

say "longest increasing subsequence: ", join(" ", lis(10, 9, 2, 5, 3, 7, 101, 18, 4, 19));
