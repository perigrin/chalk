# A priority queue as a binary heap in an array, with closures for its
# operations: insertion, removal of the least, a heap sort, merging
# k sorted lists, and a running median from two heaps.
use v5.42;

sub make_heap ($less = sub ($x, $y) { $x < $y }) {
    my @h;
    my $up = sub ($i) {
        while ($i > 0) {
            my $p = ($i - 1 - ($i - 1) % 2) / 2;
            last unless $less->($h[$i], $h[$p]);
            @h[$i, $p] = @h[$p, $i];
            $i = $p;
        }
    };
    my $down = sub ($i) {
        my $n = @h;
        while (1) {
            my ($l, $r, $m) = (2 * $i + 1, 2 * $i + 2, $i);
            $m = $l if $l < $n && $less->($h[$l], $h[$m]);
            $m = $r if $r < $n && $less->($h[$r], $h[$m]);
            last if $m == $i;
            @h[$i, $m] = @h[$m, $i];
            $i = $m;
        }
    };
    return {
        insert => sub ($x) { push @h, $x; $up->($#h) },
        pop    => sub () {
            return undef unless @h;
            my $top = $h[0];
            my $last = pop @h;
            if (@h) { $h[0] = $last; $down->(0) }
            return $top;
        },
        peek   => sub () { $h[0] },
        size   => sub () { scalar(@h) },
    };
}

my $pq = make_heap();
$pq->{insert}->($_) for 5, 3, 8, 1, 9, 2, 7;
my @out;
while ($pq->{size}->()) { push @out, $pq->{pop}->() }
say "heap order: @out";

my $tasks = make_heap(sub ($x, $y) { $x->[0] < $y->[0] || ($x->[0] == $y->[0] && $x->[1] lt $y->[1]) });
$tasks->{insert}->($_) for [3, "write tests"], [1, "fix the build"], [2, "review"], [1, "answer mail"], [5, "lunch"];
while (my $t = $tasks->{pop}->()) {
    say "priority $t->[0]: $t->[1]";
}

my @lists = ([1, 4, 9, 16], [2, 3, 5, 7, 11], [0, 10, 20], []);
my $merge = make_heap(sub ($x, $y) { $x->[0] < $y->[0] });
for my $i (0 .. $#lists) {
    $merge->{insert}->([$lists[$i][0], $i, 0]) if @{ $lists[$i] };
}
my @merged;
while (defined(my $e = $merge->{pop}->())) {
    my ($v, $li, $pos) = $e->@*;
    push @merged, $v;
    $merge->{insert}->([$lists[$li][$pos + 1], $li, $pos + 1]) if $pos + 1 < @{ $lists[$li] };
}
say "merged: @merged";

my $low = make_heap(sub ($x, $y) { $x > $y });
my $high = make_heap();
my @medians;
for my $x (5, 15, 1, 3, 8, 7, 9, 10, 20, 2) {
    if (!$low->{size}->() || $x <= $low->{peek}->()) { $low->{insert}->($x) } else { $high->{insert}->($x) }
    if ($low->{size}->() > $high->{size}->() + 1) { $high->{insert}->($low->{pop}->()) }
    elsif ($high->{size}->() > $low->{size}->()) { $low->{insert}->($high->{pop}->()) }
    push @medians, $low->{size}->() > $high->{size}->() ? $low->{peek}->() : ($low->{peek}->() + $high->{peek}->()) / 2;
}
say "running medians: @medians";
