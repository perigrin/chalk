# Mutual recursion, from Opal's tests/004-even-odd.test.ts (stevan/pp).
use v5.42;
no warnings 'recursion';

sub is_even ($n) {
    return true if $n == 0;
    return is_odd($n - 1);
}

sub is_odd ($n) {
    return false if $n == 0;
    return is_even($n - 1);
}

for my $n (0, 1, 2, 7, 10, 99, 100, 1000) {
    say "$n is ", is_even($n) ? "even" : "odd";
}

my @evens = grep { is_even($_) } 1 .. 20;
my @odds  = grep { is_odd($_) } 1 .. 20;
say "evens: @evens";
say "odds:  @odds";
say "they agree with %: ", (join(",", @evens) eq join(",", grep { $_ % 2 == 0 } 1 .. 20)) ? "yes" : "no";

my %parity = map { ($_ => is_even($_) ? "even" : "odd") } 1 .. 6;
say "$_: $parity{$_}" for sort { $a <=> $b } keys %parity;

my $count = 0;
for my $n (1 .. 50) {
    next unless is_odd($n);
    $count++;
}
say "$count odd numbers up to 50";
