# Union-find with path compression and union by rank: connected
# components of a graph, the islands of a grid, and Kruskal's minimum
# spanning tree.
use v5.42;

sub make_sets (@items) {
    my %parent;
    my %rank;
    for my $x (@items) { $parent{$x} = $x; $rank{$x} = 0 }
    my $find;
    $find = sub ($x) {
        $parent{$x} = $find->($parent{$x}) if $parent{$x} ne $x;
        return $parent{$x};
    };
    my $union = sub ($x, $y) {
        my ($rx, $ry) = ($find->($x), $find->($y));
        return 0 if $rx eq $ry;
        ($rx, $ry) = ($ry, $rx) if $rank{$rx} < $rank{$ry};
        $parent{$ry} = $rx;
        $rank{$rx}++ if $rank{$rx} == $rank{$ry};
        return 1;
    };
    return ($find, $union);
}

my @people = qw(ann bob cid dee eve fay gus hal);
my ($find, $union) = make_sets(@people);
$union->($_->@*) for [qw(ann bob)], [qw(cid dee)], [qw(bob dee)], [qw(eve fay)], [qw(fay eve)];
my %groups;
push @{ $groups{ $find->($_) } }, $_ for @people;
say "groups: ", join(" | ", sort map { join(",", sort $_->@*) } values %groups);

my @grid = (
    "11000110",
    "11000100",
    "00100000",
    "00011011",
    "10000011",
);
my @land;
for my $r (0 .. $#grid) {
    for my $c (0 .. length($grid[$r]) - 1) {
        push @land, "$r,$c" if substr($grid[$r], $c, 1) eq '1';
    }
}
my %is_land = map { ($_ => 1) } @land;
my ($gfind, $gunion) = make_sets(@land);
for my $cell (@land) {
    my $comma = index($cell, ",");
    my ($r, $c) = (substr($cell, 0, $comma), substr($cell, $comma + 1));
    for my $n ("$r," . ($c + 1), ($r + 1) . ",$c") {
        $gunion->($cell, $n) if $is_land{$n};
    }
}
my %islands;
$islands{ $gfind->($_) }++ for @land;
say scalar(keys %islands), " islands, of sizes ", join(" ", sort { $b <=> $a } values %islands);

my @edges = ([7, qw(A B)], [5, qw(A D)], [8, qw(B C)], [9, qw(B D)], [7, qw(B E)], [5, qw(C E)],
             [15, qw(D E)], [6, qw(D F)], [8, qw(E F)], [9, qw(E G)], [11, qw(F G)]);
my ($kfind, $kunion) = make_sets(qw(A B C D E F G));
my ($weight, @tree) = (0);
for my $e (sort { $a->[0] <=> $b->[0] || $a->[1] cmp $b->[1] } @edges) {
    my ($w, $x, $y) = $e->@*;
    next unless $kunion->($x, $y);
    $weight += $w;
    push @tree, "$x$y($w)";
}
say "minimum spanning tree: @tree, weight $weight";
