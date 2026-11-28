# 99 bottles of beer, from Opal's tests/099-bottles-of-beer.test.ts
# (stevan/pp), first as Opal had it and then as a Perl programmer would
# write the song today.
use v5.42;

my $num = 99;
while ($num > 0) {

    my $s = '';
    unless ($num == 1) {
        $s = 's';
    }

    say($num . " bottle" . $s . " of beer on the wall, " . $num . " bottle" . $s . " of beer");

    $num = $num - 1;

    unless ($num == 1) {
        $s = 's';
    }

    if ($num == 0) {
        say("No more");
    } else {
        say("Take one down, pass it around, " . $num . " bottle" . $s . " of beer on the wall");
    }
}

say("No more bottles of beer on the wall, no more bottles of beer.");
say("Go to the store and buy some more, 99 bottles of beer on the wall.");
say "";

sub bottles ($n) {
    return "no more bottles" if $n == 0;
    return "1 bottle" if $n == 1;
    return "$n bottles";
}

for my $n (reverse 0 .. 5) {
    my $b1 = bottles($n);
    say ucfirst($b1), " of beer on the wall, $b1 of beer.";
    if ($n > 0) {
        say "Take one down and pass it around, ", bottles($n - 1), " of beer on the wall.";
    } else {
        say "Go to the store and buy some more, ", bottles(99), " of beer on the wall.";
    }
    say "" if $n;
}
