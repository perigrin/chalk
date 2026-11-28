# Permutations and combinations: recursive generators, the next
# permutation in lexical order, the power set by counting, and a check
# of each count against the formula.
use v5.42;

sub permutations (@items) {
    return ([]) unless @items;
    my @out;
    for my $i (0 .. $#items) {
        my @rest = @items;
        my ($x) = splice(@rest, $i, 1);
        push @out, [$x, $_->@*] for permutations(@rest);
    }
    return @out;
}

sub combinations ($k, @items) {
    return ([]) if $k == 0;
    return () if @items < $k;
    my ($first, @rest) = @items;
    return ((map { [$first, $_->@*] } combinations($k - 1, @rest)),
            combinations($k, @rest));
}

sub next_permutation (@a) {
    my $i = $#a - 1;
    $i-- while $i >= 0 && $a[$i] ge $a[$i + 1];
    return () if $i < 0;
    my $j = $#a;
    $j-- while $a[$j] le $a[$i];
    @a[$i, $j] = @a[$j, $i];
    @a[$i + 1 .. $#a] = reverse @a[$i + 1 .. $#a];
    return @a;
}

sub power_set (@items) {
    my @sets;
    for my $mask (0 .. 2 ** @items - 1) {
        my @set;
        my $m = $mask;
        for my $item (@items) {
            push @set, $item if $m % 2;
            $m = ($m - $m % 2) / 2;
        }
        push @sets, \@set;
    }
    return @sets;
}

sub fact ($n) { $n <= 1 ? 1 : $n * fact($n - 1) }

my @p = permutations(qw(a b c));
say "permutations of a b c: ", join(" ", map { join("", $_->@*) } @p);
for my $n (1 .. 6) {
    my @all = permutations(1 .. $n);
    my $count = @all;
    say "$n items: $count permutations (", fact($n), ")";
}

say "3 of 5: ", join(" ", map { join("", $_->@*) } combinations(3, qw(a b c d e)));
for my $k (0 .. 6) {
    my @c = combinations($k, 1 .. 6);
    printf "C(6, %d) = %2d %s\n", $k, scalar(@c), scalar(@c) == fact(6) / (fact($k) * fact(6 - $k)) ? "ok" : "WRONG";
}

my @w = qw(a b c d);
my $steps = 0;
while (@w) {
    print join("", @w), " ";
    $steps++;
    @w = next_permutation(@w);
}
print "\n$steps in lexical order\n";

my @ps = power_set(qw(x y z));
say "power set: ", join(" ", map { "{" . join(",", $_->@*) . "}" } @ps);
