# The n-queens puzzle by backtracking: count the solutions for each n up
# to 8, and draw the first solution for 8.
use v5.42;

my @solutions;

sub safe ($cols, $row, $col) {
    for my $r (0 .. $cols->$#*) {
        my $c = $cols->[$r];
        return 0 if $c == $col;
        my $dist = $c > $col ? $c - $col : $col - $c;
        return 0 if $dist == $row - $r;
    }
    return 1;
}

sub place ($n, $cols) {
    my $row = $cols->@*;
    if ($row == $n) {
        push @solutions, [$cols->@*];
        return;
    }
    for my $col (0 .. $n - 1) {
        next unless safe($cols, $row, $col);
        push $cols->@*, $col;
        place($n, $cols);
        pop $cols->@*;
    }
}

for my $n (1 .. 8) {
    @solutions = ();
    place($n, []);
    printf "%d queens: %3d solutions\n", $n, scalar(@solutions);
}

my $first = $solutions[0];
for my $c ($first->@*) {
    print join(" ", map { $_ == $c ? "Q" : "." } 0 .. 7), "\n";
}
my %by_first;
$by_first{$_->[0]}++ for @solutions;
print "first column $_: $by_first{$_}\n" for sort keys %by_first;
