# Memoisation with a hash: a general memoiser over closures, the number
# of calls it saves, and three problems it makes quick (partitions,
# lattice paths, the longest common subsequence).
use v5.42;
no warnings 'recursion';

my %calls;

sub memoize ($name, $f) {
    my %cache;
    return sub (@args) {
        my $key = join(",", @args);
        $calls{$name}++;
        return $cache{$key} if exists $cache{$key};
        my $v = $f->(@args);
        $cache{$key} = $v;
        return $v;
    };
}

my $partitions;
$partitions = memoize("partitions", sub ($n, $max) {
    return 1 if $n == 0;
    return 0 if $n < 0 || $max == 0;
    return $partitions->($n - $max, $max) + $partitions->($n, $max - 1);
});

my $paths;
$paths = memoize("paths", sub ($r, $c) {
    return 1 if $r == 0 || $c == 0;
    return $paths->($r - 1, $c) + $paths->($r, $c - 1);
});

for my $n (1, 5, 10, 50, 100) {
    say "p($n) = ", $partitions->($n, $n);
}
say "lattice paths through a 16x16 grid: ", $paths->(16, 16);
say "$_ was called $calls{$_} times" for sort keys %calls;

sub lcs ($x, $y) {
    my %memo;
    my $go;
    $go = sub ($i, $j) {
        return "" if $i == length($x) || $j == length($y);
        my $key = "$i,$j";
        return $memo{$key} if exists $memo{$key};
        my $r;
        if (substr($x, $i, 1) eq substr($y, $j, 1)) {
            $r = substr($x, $i, 1) . $go->($i + 1, $j + 1);
        } else {
            my $p = $go->($i + 1, $j);
            my $q = $go->($i, $j + 1);
            $r = length($p) >= length($q) ? $p : $q;
        }
        $memo{$key} = $r;
        return $r;
    };
    my $answer = $go->(0, 0);
    return ($answer, scalar(keys %memo));
}

for my $pair (["AGGTAB", "GXTXAYB"], ["thisisatest", "testing123testing"], ["perl", "pearl"]) {
    my ($s, $t) = $pair->@*;
    my ($common, $cells) = lcs($s, $t);
    say "lcs($s, $t) = '$common' (", length($common), " long, $cells cells)";
}
