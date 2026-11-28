# A maze read from a heredoc, solved by breadth-first search for the
# shortest path and by depth-first search for any path, each drawn, with
# the cells that can't be reached counted.
use v5.42;

# No split yet (step 20): the heredoc's lines, by index.
sub lines ($s) {
    my @out;
    my $pos = 0;
    while ((my $nl = index($s, "\n", $pos)) >= 0) {
        push @out, substr($s, $pos, $nl - $pos);
        $pos = $nl + 1;
    }
    return @out;
}

my @maze = lines(<<'END');
###############
#S    #       #
# ### # ##### #
# #   #     # #
# # ####### # #
# #       # # #
# ####### # # #
#       #   #E#
####### ##### #
#     #       #
# ### ######  #
#   #         #
###############
END

my ($rows, $cols) = (scalar(@maze), length $maze[0]);
my %start;
my %end;
for my $r (0 .. $rows - 1) {
    for my $c (0 .. $cols - 1) {
        my $ch = substr($maze[$r], $c, 1);
        %start = (r => $r, c => $c) if $ch eq 'S';
        %end = (r => $r, c => $c) if $ch eq 'E';
    }
}

sub open_cell ($r, $c) {
    return 0 if $r < 0 || $c < 0 || $r >= $rows || $c >= $cols;
    return substr($maze[$r], $c, 1) ne '#';
}

my @dirs = ([-1, 0], [0, 1], [1, 0], [0, -1]);

sub bfs () {
    my %prev = ("$start{r},$start{c}" => '');
    my @queue = ([$start{r}, $start{c}]);
    while (@queue) {
        my ($r, $c) = @{ shift @queue };
        return \%prev if $r == $end{r} && $c == $end{c};
        for my $d (@dirs) {
            my ($nr, $nc) = ($r + $d->[0], $c + $d->[1]);
            next unless open_cell($nr, $nc);
            next if exists $prev{"$nr,$nc"};
            $prev{"$nr,$nc"} = "$r,$c";
            push @queue, [$nr, $nc];
        }
    }
    return \%prev;
}

sub draw ($mark, %cells) {
    my @out = @maze;
    for my $cell (sort keys %cells) {
        my $comma = index($cell, ",");
        my ($r, $c) = (substr($cell, 0, $comma), substr($cell, $comma + 1));
        next unless substr($out[$r], $c, 1) eq ' ';
        $out[$r] = substr($out[$r], 0, $c) . $mark . substr($out[$r], $c + 1);
    }
    say $_ for @out;
}

my $prev = bfs();
my %path;
my $at = "$end{r},$end{c}";
while ($prev->{$at} ne '') {
    $at = $prev->{$at};
    $path{$at} = 1;
}
say "shortest path: ", scalar(keys %path), " steps";
draw('.', %path);

my %seen;
my @found;
sub dfs ($r, $c, @trail) {
    return 0 if !open_cell($r, $c) || $seen{"$r,$c"}++;
    if ($r == $end{r} && $c == $end{c}) { @found = @trail; return 1 }
    for my $d (@dirs) {
        return 1 if dfs($r + $d->[0], $c + $d->[1], @trail, "$r,$c");
    }
    return 0;
}
dfs($start{r}, $start{c});
say "a depth-first path: ", scalar(@found), " steps";

my $open = 0;
for my $r (0 .. $rows - 1) {
    $open += grep { substr($maze[$r], $_, 1) ne '#' } 0 .. $cols - 1;
}
say "open cells: $open, reached by the search: ", scalar(keys $prev->%*);
