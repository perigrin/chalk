# Run-length encoding and decoding of strings, checked by a round trip,
# with the ratio of each, and the look-and-say sequence, which is
# run-length encoding applied to itself.
use v5.42;

sub encode ($s) {
    my $out = "";
    my $i = 0;
    while ($i < length $s) {
        my $c = substr($s, $i, 1);
        my $n = 1;
        $n++ while $i + $n < length($s) && substr($s, $i + $n, 1) eq $c;
        $out .= ($n > 1 ? $n : "") . $c;
        $i += $n;
    }
    return $out;
}

sub decode ($s) {
    my $out = "";
    my $n = "";
    for my $i (0 .. length($s) - 1) {
        my $c = substr($s, $i, 1);
        if ($c ge "0" && $c le "9") {
            $n .= $c;
        } else {
            $out .= $c x ($n eq "" ? 1 : $n);
            $n = "";
        }
    }
    return $out;
}

sub look_and_say ($s) {
    my $out = "";
    my $i = 0;
    while ($i < length $s) {
        my $c = substr($s, $i, 1);
        my $n = 1;
        $n++ while $i + $n < length($s) && substr($s, $i + $n, 1) eq $c;
        $out .= "$n$c";
        $i += $n;
    }
    return $out;
}

for my $s ("WWWWWWWWWWWWBWWWWWWWWWWWWBBBWWWWWWWWWWWWWWWWWWWWWWWWBWWWWWWWWWWWWWW",
           "abc", "aabcccccaaa", "x" x 30, "") {
    my $e = encode($s);
    my $back = decode($e);
    die "round trip failed for '$s'\n" unless $back eq $s;
    my $ratio = length($s) ? sprintf("%.0f%%", 100 * length($e) / length($s)) : "-";
    say "'$e' ($ratio)";
}

my $term = "1";
for my $i (1 .. 12) {
    say sprintf("%2d %s", $i, length($term) > 40 ? substr($term, 0, 40) . "... (" . length($term) . ")" : $term);
    $term = look_and_say($term);
}
