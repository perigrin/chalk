# Dijkstra's shortest paths on a small weighted graph held as a hash of
# hashes, with the paths rebuilt from the predecessors, and a check by
# Bellman-Ford.
use v5.42;

my %graph = (
    A => { B => 7, C => 9, F => 14 },
    B => { A => 7, C => 10, D => 15 },
    C => { A => 9, B => 10, D => 11, F => 2 },
    D => { B => 15, C => 11, E => 6 },
    E => { D => 6, F => 9 },
    F => { A => 14, C => 2, E => 9 },
    G => { H => 1 },
    H => { G => 1 },
);

sub dijkstra ($g, $source) {
    my %dist = ($source => 0);
    my %prev;
    my %done;
    while (1) {
        my ($u) = sort { $dist{$a} <=> $dist{$b} || $a cmp $b } grep { !$done{$_} } keys %dist;
        last unless defined $u;
        $done{$u} = 1;
        for my $v (sort keys %{ $g->{$u} }) {
            my $alt = $dist{$u} + $g->{$u}{$v};
            if (!defined $dist{$v} || $alt < $dist{$v}) {
                $dist{$v} = $alt;
                $prev{$v} = $u;
            }
        }
    }
    return (\%dist, \%prev);
}

sub path ($prev, $to) {
    my @p = ($to);
    unshift @p, $prev->{$p[0]} while exists $prev->{$p[0]};
    return @p;
}

sub bellman_ford ($g, $source) {
    my %dist = ($source => 0);
    my @nodes = sort keys $g->%*;
    for (1 .. $#nodes) {
        for my $u (@nodes) {
            next unless defined $dist{$u};
            for my $v (sort keys %{ $g->{$u} }) {
                my $alt = $dist{$u} + $g->{$u}{$v};
                $dist{$v} = $alt if !defined $dist{$v} || $alt < $dist{$v};
            }
        }
    }
    return \%dist;
}

my ($dist, $prev) = dijkstra(\%graph, 'A');
for my $node (sort keys %graph) {
    if (defined $dist->{$node}) {
        printf "A to %s: %2d via %s\n", $node, $dist->{$node}, join("-", path($prev, $node));
    } else {
        say "A to $node: unreachable";
    }
}

my $check = bellman_ford(\%graph, 'A');
my @wrong = grep { ($check->{$_} // -1) != ($dist->{$_} // -1) } sort keys %graph;
say "Bellman-Ford agrees: ", @wrong ? "no (@wrong)" : "yes";

my ($far, $far_d) = ('', -1);
for my $s (sort keys %graph) {
    my ($d) = dijkstra(\%graph, $s);
    for my $t (sort keys $d->%*) {
        ($far, $far_d) = ("$s-$t", $d->{$t}) if $d->{$t} > $far_d;
    }
}
say "the two nodes furthest apart: $far, $far_d";
