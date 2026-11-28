# A sudoku solver by backtracking with the most constrained cell first;
# the puzzle is read from a heredoc, solved, printed and checked.
use v5.42;

my $puzzle = <<'END';
53..7....
6..195...
.98....6.
8...6...3
4..8.3..1
7...2...6
.6....28.
...419..5
....8.79.
END

# No split yet (step 20): nine lines of ten characters, the newline last.
my @grid;
for my $r (0 .. 8) {
    $grid[$r] = [ map { my $c = substr($puzzle, $r * 10 + $_, 1); $c eq '.' ? 0 : $c } 0 .. 8 ];
}

sub candidates ($row, $col) {
    my %used;
    for my $i (0 .. 8) {
        $used{ $grid[$row][$i] } = 1;
        $used{ $grid[$i][$col] } = 1;
    }
    my ($br, $bc) = ($row - $row % 3, $col - $col % 3);
    for my $i ($br .. $br + 2) {
        for my $j ($bc .. $bc + 2) {
            $used{ $grid[$i][$j] } = 1;
        }
    }
    return grep { !$used{$_} } 1 .. 9;
}

my $tries = 0;
sub solve () {
    my ($best_r, $best_c, @best);
    for my $i (0 .. 8) {
        for my $j (0 .. 8) {
            next if $grid[$i][$j];
            my @c = candidates($i, $j);
            return 0 unless @c;
            if (!defined $best_r || @c < @best) {
                ($best_r, $best_c, @best) = ($i, $j, @c);
            }
        }
    }
    return 1 unless defined $best_r;
    for my $v (@best) {
        $tries++;
        $grid[$best_r][$best_c] = $v;
        return 1 if solve();
    }
    $grid[$best_r][$best_c] = 0;
    return 0;
}

sub show () {
    for my $i (0 .. 8) {
        say join(" ", map { join("", $grid[$i]->@[$_ * 3 .. $_ * 3 + 2]) } 0 .. 2);
        say "" if $i % 3 == 2 && $i < 8;
    }
}

sub valid () {
    for my $i (0 .. 8) {
        my %row;
        my %col;
        my %box;
        for my $j (0 .. 8) {
            $row{ $grid[$i][$j] }++;
            $col{ $grid[$j][$i] }++;
            $box{ $grid[$i - $i % 3 + ($j - $j % 3) / 3][3 * ($i % 3) + $j % 3] }++;
        }
        return 0 unless keys %row == 9 && keys %col == 9 && keys %box == 9;
    }
    return 1;
}

my $given = grep { $_ } map { $_->@* } @grid;
say "$given clues given";
say solve() ? "solved after $tries tries:" : "no solution";
show();
say valid() ? "every row, column and box holds 1 to 9" : "INVALID";
