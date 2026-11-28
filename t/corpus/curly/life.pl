# Conway's Game of Life on a small grid that wraps at its edges: a
# glider and a blinker, generation by generation, with the population
# and a check that the glider comes back moved one cell diagonally.
use v5.42;

my ($rows, $cols) = (10, 12);

sub empty_grid () {
    return [ map { [ (0) x $cols ] } 1 .. $rows ];
}

sub place ($grid, $r0, $c0, @cells) {
    for my $cell (@cells) {
        my ($r, $c) = $cell->@*;
        $grid->[($r0 + $r) % $rows][($c0 + $c) % $cols] = 1;
    }
}

sub neighbours ($grid, $r, $c) {
    my $n = 0;
    for my $dr (-1, 0, 1) {
        for my $dc (-1, 0, 1) {
            next if $dr == 0 && $dc == 0;
            $n += $grid->[($r + $dr) % $rows][($c + $dc) % $cols];
        }
    }
    return $n;
}

sub step ($grid) {
    my $next = empty_grid();
    for my $r (0 .. $rows - 1) {
        for my $c (0 .. $cols - 1) {
            my $n = neighbours($grid, $r, $c);
            $next->[$r][$c] = ($n == 3 || ($n == 2 && $grid->[$r][$c])) ? 1 : 0;
        }
    }
    return $next;
}

sub show ($grid, $gen) {
    my $pop = 0;
    $pop += $_ for map { $_->@* } $grid->@*;
    say "generation $gen, population $pop";
    say join("", map { $_ ? "#" : "." } $_->@*) for $grid->@*;
}

sub same ($x, $y) {
    for my $r (0 .. $rows - 1) {
        for my $c (0 .. $cols - 1) {
            return 0 unless $x->[$r][$c] == $y->[$r][$c];
        }
    }
    return 1;
}

my @glider = ([0, 1], [1, 2], [2, 0], [2, 1], [2, 2]);
my @blinker = ([0, 0], [0, 1], [0, 2]);

my $grid = empty_grid();
place($grid, 0, 0, @glider);
place($grid, 6, 7, @blinker);
show($grid, 0);
for my $gen (1 .. 4) {
    $grid = step($grid);
    show($grid, $gen) if $gen % 2 == 0;
}

my $expect = empty_grid();
place($expect, 1, 1, @glider);
place($expect, 6, 7, @blinker);
say "after 4 generations the glider has moved by (1, 1): ", same($grid, $expect) ? "yes" : "no";

my $g = empty_grid();
place($g, 0, 0, @glider);
for (1 .. 4 * $rows * $cols / 2) { $g = step($g) }
my $home = empty_grid();
place($home, 0, 0, @glider);
my $lcm_moves = 4 * 60;
$g = step($g) for 1 .. $lcm_moves - 4 * $rows * $cols / 2;
say "after $lcm_moves generations it is home again: ", same($g, $home) ? "yes" : "no";
