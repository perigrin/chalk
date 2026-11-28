# Noughts and crosses with minimax: the computer plays itself from an
# opening (a draw, as it must), then finds the best move in three set
# positions, and counts the games the tree holds.
use v5.42;
no warnings 'recursion';

my @lines = ([0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]);

sub winner (@b) {
    for my $l (@lines) {
        my ($x, $y, $z) = @b[$l->@*];
        return $x if $x ne '.' && $x eq $y && $y eq $z;
    }
    return (grep { $_ eq '.' } @b) ? undef : 'draw';
}

my $nodes = 0;
sub minimax ($player, @b) {
    $nodes++;
    my $w = winner(@b);
    if (defined $w) {
        return (0, undef) if $w eq 'draw';
        return ($w eq 'X' ? 1 : -1, undef);
    }
    my ($best, $best_move);
    for my $i (grep { $b[$_] eq '.' } 0 .. 8) {
        my @next = @b;
        $next[$i] = $player;
        my ($score) = minimax($player eq 'X' ? 'O' : 'X', @next);
        if (!defined $best || ($player eq 'X' ? $score > $best : $score < $best)) {
            ($best, $best_move) = ($score, $i);
        }
    }
    return ($best, $best_move);
}

sub show (@b) {
    say "  ", join(" ", @b[$_ * 3 .. $_ * 3 + 2]) for 0 .. 2;
}

# From an empty board the tree is 549,946 positions: too many for a test
# that collects at every allocation, so the game starts two moves in.
my @board = ('X', '.', '.', '.', 'O', '.', '.', '.', '.');
my $player = 'X';
my $moves = 2;
until (defined winner(@board)) {
    my (undef, $move) = minimax($player, @board);
    $board[$move] = $player;
    $moves++;
    $player = $player eq 'X' ? 'O' : 'X';
}
show(@board);
say "result after $moves moves: ", winner(@board), "; $nodes positions looked at";

for my $pos (["XX.OO....", 'X'], ["X.O.X..O.", 'O'], ["O.X.X....", 'O']) {
    my @b = map { substr($pos->[0], $_, 1) } 0 .. 8;
    $nodes = 0;
    my ($score, $move) = minimax($pos->[1], @b);
    say "$pos->[0] with $pos->[1] to play: move to $move, worth $score ($nodes positions)";
}

my %ends;
sub count_games ($player, @b) {
    my $w = winner(@b);
    if (defined $w) { $ends{$w}++; return }
    for my $i (grep { $b[$_] eq '.' } 0 .. 8) {
        my @next = @b;
        $next[$i] = $player;
        count_games($player eq 'X' ? 'O' : 'X', @next);
    }
}
count_games('X', 'X', '.', '.', '.', 'O', '.', '.', '.', '.');
my $total = 0;
$total += $ends{$_} for sort keys %ends;
say "$total possible games after X in a corner and O in the centre: ", join(", ", map { "$_ $ends{$_}" } sort keys %ends);
