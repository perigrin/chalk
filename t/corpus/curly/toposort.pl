# Topological sort of a build's dependencies, by Kahn's algorithm and by
# depth-first search, with the build in levels, and a cycle detected.
use v5.42;

my %deps = (
    app      => [qw(lib ui config)],
    lib      => [qw(core util)],
    ui       => [qw(lib widgets)],
    widgets  => [qw(core)],
    config   => [],
    core     => [],
    util     => [qw(core)],
    tests    => [qw(app util)],
);

sub kahn (%d) {
    my %indegree = map { ($_ => scalar(@{ $d{$_} })) } sort keys %d;
    my %users;
    for my $n (sort keys %d) {
        push @{ $users{$_} }, $n for @{ $d{$n} };
    }
    my @ready = sort grep { $indegree{$_} == 0 } keys %indegree;
    my @order;
    while (@ready) {
        my $n = shift @ready;
        push @order, $n;
        for my $u (sort @{ $users{$n} // [] }) {
            push @ready, $u if --$indegree{$u} == 0;
        }
        @ready = sort @ready;
    }
    my $stuck = join(" ", sort grep { $indegree{$_} > 0 } keys %indegree);
    die "cycle among: $stuck\n" if @order < scalar(keys %d);
    return @order;
}

sub dfs_order (%d) {
    my (%state, @order);
    my $visit;
    $visit = sub ($n, @path) {
        return if ($state{$n} // '') eq 'done';
        die "cycle: " . join(" -> ", @path, $n) . "\n" if ($state{$n} // '') eq 'active';
        $state{$n} = 'active';
        $visit->($_, @path, $n) for sort @{ $d{$n} };
        $state{$n} = 'done';
        push @order, $n;
    };
    $visit->($_) for sort keys %d;
    return @order;
}

sub levels (%d) {
    my %level;
    my $depth;
    $depth = sub ($n) {
        return $level{$n} if defined $level{$n};
        my $max = -1;
        for my $m (@{ $d{$n} }) {
            my $l = $depth->($m);
            $max = $l if $l > $max;
        }
        $level{$n} = $max + 1;
        return $max + 1;
    };
    $depth->($_) for sort keys %d;
    my @by;
    push @{ $by[$level{$_}] }, $_ for sort keys %level;
    return @by;
}

say "Kahn: ", join(" ", kahn(%deps));
say "DFS:  ", join(" ", dfs_order(%deps));
my @lv = levels(%deps);
say "level $_: @{ $lv[$_] }" for 0 .. $#lv;

my %cyclic = (%deps, core => [qw(tests)]);
for my $sorter (\&kahn, \&dfs_order) {
    try {
        $sorter->(map { ($_ => $cyclic{$_}) } sort keys %cyclic);
    } catch ($e) {
        print "cyclic: $e";
    }
}
