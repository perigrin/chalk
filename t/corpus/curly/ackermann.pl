# Ackermann's function, from Opal's author/TESTING.md (stevan/pp), with
# a table of small values, a count of calls, and the closed forms for
# m up to 3 to check it against.
use v5.42;
no warnings 'recursion';

my $calls = 0;
my $deepest = 0;

sub ackermann ($m, $n, $depth = 1) {
    $calls++;
    $deepest = $depth if $depth > $deepest;
    if ($m == 0) {
        return $n + 1;
    } elsif ($n == 0) {
        return ackermann($m - 1, 1, $depth + 1);
    } else {
        return ackermann($m - 1, ackermann($m, $n - 1, $depth + 1), $depth + 1);
    }
}

sub closed_form ($m, $n) {
    return $n + 1 if $m == 0;
    return $n + 2 if $m == 1;
    return 2 * $n + 3 if $m == 2;
    return 2 ** ($n + 3) - 3 if $m == 3;
    die "no closed form for m = $m\n";
}

print "m\\n";
printf("%6d", $_) for 0 .. 5;
print "\n";
for my $m (0 .. 3) {
    printf("%3d", $m);
    my $limit = $m == 3 ? 4 : 5;
    for my $n (0 .. $limit) {
        my $v = ackermann($m, $n);
        my $c = closed_form($m, $n);
        die "A($m, $n) = $v, but the closed form says $c\n" unless $v == $c;
        printf("%6d", $v);
    }
    print "\n";
}

for my $case ([2, 3], [3, 3], [3, 4]) {
    my ($m, $n) = $case->@*;
    ($calls, $deepest) = (0, 0);
    my $v = ackermann($m, $n);
    say "A($m, $n) = $v after $calls calls, at most $deepest deep";
}

try {
    closed_form(4, 1);
} catch ($e) {
    print "closed_form(4, 1): $e";
}
