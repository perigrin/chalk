# Sorting algorithms written out: quicksort, mergesort, insertion sort
# and heapsort, each checked against perl's sort, with comparisons counted.
use v5.42;

my %compares;

sub quicksort (@list) {
    return @list if @list <= 1;
    my ($pivot, @rest) = @list;
    my @less = grep { $compares{quick}++; $_ < $pivot } @rest;
    my @more = grep { $_ >= $pivot } @rest;
    return (quicksort(@less), $pivot, quicksort(@more));
}

sub merge_lists ($x, $y) {
    my @out;
    my ($i, $j) = (0, 0);
    while ($i < $x->@* && $j < $y->@*) {
        $compares{merge}++;
        if ($x->[$i] <= $y->[$j]) {
            push @out, $x->[$i++];
        } else {
            push @out, $y->[$j++];
        }
    }
    push @out, $x->@[$i .. $x->$#*], $y->@[$j .. $y->$#*];
    return @out;
}

sub mergesort (@list) {
    return @list if @list <= 1;
    my $n = @list;
    my $mid = ($n - $n % 2) / 2;
    my @left  = mergesort(@list[0 .. $mid - 1]);
    my @right = mergesort(@list[$mid .. $#list]);
    return merge_lists(\@left, \@right);
}

sub insertion_sort (@a) {
    my $last = $#a;
    for my $i (1 .. $last) {
        my $v = $a[$i];
        my $j = $i - 1;
        while ($j >= 0 && $a[$j] > $v) {
            $compares{insertion}++;
            $a[$j + 1] = $a[$j];
            $j--;
        }
        $a[$j + 1] = $v;
    }
    return @a;
}

sub heapsort (@a) {
    my $n = @a;
    my $sift = sub ($start, $end) {
        my $root = $start;
        while (2 * $root + 1 <= $end) {
            my $child = 2 * $root + 1;
            $child++ if $child + 1 <= $end && $a[$child] < $a[$child + 1];
            $compares{heap}++;
            return if $a[$root] >= $a[$child];
            @a[$root, $child] = @a[$child, $root];
            $root = $child;
        }
    };
    for (my $start = ($n - 2 - $n % 2) / 2; $start >= 0; $start--) {
        $sift->($start, $n - 1);
    }
    for (my $end = $n - 1; $end > 0; $end--) {
        @a[0, $end] = @a[$end, 0];
        $sift->(0, $end - 1);
    }
    return @a;
}

# A small linear congruential generator, so the data is the same everywhere.
my $seed = 42;
sub rand_int ($max) {
    $seed = ($seed * 1103515245 + 12345) % 2147483648;
    return $seed % $max;
}

my @data = map { rand_int(1000) } 1 .. 200;
my @expect = sort { $a <=> $b } @data;
say "data starts: @data[0 .. 9]";
say "sorted:      @expect[0 .. 9] ... $expect[-1]";

my %sorts = (
    quick     => \&quicksort,
    merge     => \&mergesort,
    insertion => \&insertion_sort,
    heap      => \&heapsort,
);
for my $name (sort keys %sorts) {
    my @got = $sorts{$name}->(@data);
    my $ok = "@got" eq "@expect" ? "ok" : "WRONG";
    printf "%-10s %s, %5d comparisons\n", $name, $ok, $compares{$name};
}

my @words = qw(pear Apple banana cherry apple Banana date);
say join " ", sort @words;
say join " ", sort { lc($a) cmp lc($b) or $a cmp $b } @words;
say join " ", reverse sort { length($a) <=> length($b) } @words;
