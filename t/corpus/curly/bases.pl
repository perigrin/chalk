# Base conversion by hand: any base from 2 to 36 both ways, without
# int, oct or hex (none is in the language yet: the remainder is taken
# off before dividing), then checked against sprintf's %b, %o and %x.
use v5.42;

my @digits = (0 .. 9, map { chr(ord('a') + $_) } 0 .. 25);
my %digit_value = map { ($digits[$_] => $_) } 0 .. $#digits;

sub to_base ($n, $base) {
    die "base $base is out of range\n" if $base < 2 || $base > 36;
    return "0" if $n == 0;
    my $sign = $n < 0 ? "-" : "";
    $n = -$n if $n < 0;
    my $out = "";
    while ($n > 0) {
        my $d = $n % $base;
        $out = $digits[$d] . $out;
        $n = ($n - $d) / $base;
    }
    return $sign . $out;
}

sub from_base ($s, $base) {
    my $n = 0;
    my $sign = 1;
    if (substr($s, 0, 1) eq '-') {
        $sign = -1;
        $s = substr($s, 1);
    }
    $s = lc $s;
    for my $i (0 .. length($s) - 1) {
        my $c = substr($s, $i, 1);
        my $v = $digit_value{$c};
        die "'$c' is not a digit in base $base\n" unless defined $v && $v < $base;
        $n = $n * $base + $v;
    }
    return $sign * $n;
}

for my $n (0, 1, 10, 255, 1000, 65535, -42, 2026) {
    printf "%6d: %-17s %-7s %-5s %s\n", $n, map { to_base($n, $_) } 2, 8, 16, 36;
}

my $mismatch = 0;
for my $n (0 .. 5000) {
    $mismatch++ unless to_base($n, 2) eq sprintf("%b", $n)
                    && to_base($n, 8) eq sprintf("%o", $n)
                    && to_base($n, 16) eq sprintf("%x", $n);
    for my $base (2, 3, 7, 16, 36) {
        $mismatch++ unless from_base(to_base($n, $base), $base) == $n;
    }
}
say "mismatches up to 5000: $mismatch";

say "ff in base 16 is ", from_base("ff", 16);
say "zz in base 36 is ", from_base("zz", 36);
say "the largest integer is ", to_base(9223372036854775807, 16), " in hex";
for my $bad (["12", 2], ["g", 16]) {
    try {
        from_base($bad->@*);
    } catch ($e) {
        print "from_base($bad->[0], $bad->[1]): $e";
    }
}
