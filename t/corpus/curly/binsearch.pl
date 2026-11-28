# Binary search, by loop and by recursion, over sorted numbers and words;
# the insertion point when a value is missing; and the count of probes.
use v5.42;

sub bsearch ($list, $target) {
    my ($lo, $hi) = (0, $list->$#*);
    my $probes = 0;
    while ($lo <= $hi) {
        my $mid = ($lo + $hi - ($lo + $hi) % 2) / 2;
        $probes++;
        if ($list->[$mid] == $target) {
            return ($mid, $probes);
        } elsif ($list->[$mid] < $target) {
            $lo = $mid + 1;
        } else {
            $hi = $mid - 1;
        }
    }
    return (-1 - $lo, $probes);
}

sub bsearch_str ($list, $target, $lo = 0, $hi = $list->$#*) {
    return -1 if $lo > $hi;
    my $mid = ($lo + $hi - ($lo + $hi) % 2) / 2;
    my $c = $list->[$mid] cmp $target;
    return $mid if $c == 0;
    return $c < 0 ? bsearch_str($list, $target, $mid + 1, $hi)
                  : bsearch_str($list, $target, $lo, $mid - 1);
}

my @squares = map { $_ * $_ } 0 .. 100;
for my $t (0, 1, 49, 50, 2500, 9999, 10000, 10001) {
    my ($i, $probes) = bsearch(\@squares, $t);
    if ($i >= 0) {
        say "$t is at $i ($probes probes)";
    } else {
        my $at = -1 - $i;
        say "$t is missing; it would go at $at ($probes probes)";
    }
}

my @words = sort qw(apple banana cherry date elder fig grape kiwi lemon mango);
for my $w (qw(apple fig mango zucchini aardvark)) {
    my $i = bsearch_str(\@words, $w);
    say $i >= 0 ? "$w at $i" : "$w not found";
}

my $worst = 0;
for my $t (0 .. 10000) {
    my (undef, $p) = bsearch(\@squares, $t);
    $worst = $p if $p > $worst;
}
say "never more than $worst probes over ", scalar(@squares), " values";
