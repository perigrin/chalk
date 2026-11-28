# The Luhn checksum: validate card-like numbers, compute check digits,
# and find the single-digit typos it catches.
use v5.42;

sub luhn_sum ($digits) {
    my $sum = 0;
    my $double = 0;
    for my $i (reverse 0 .. length($digits) - 1) {
        my $d = substr($digits, $i, 1);
        if ($double) {
            $d *= 2;
            $d -= 9 if $d > 9;
        }
        $sum += $d;
        $double = !$double;
    }
    return $sum;
}

sub luhn_valid ($number) {
    my $digits = "";
    for my $i (0 .. length($number) - 1) {
        my $c = substr($number, $i, 1);
        next if $c eq " ";
        return 0 unless $c ge "0" && $c le "9";
        $digits .= $c;
    }
    return 0 unless length($digits) >= 2;
    return luhn_sum($digits) % 10 == 0;
}

sub check_digit ($partial) {
    my $sum = luhn_sum($partial . "0");
    return (10 - $sum % 10) % 10;
}

for my $n ("4539 3195 0343 6467", "8273 1232 7352 0569", "79927398713",
           "0", "059", "1234 5678 9012 3456", "abc") {
    printf "%-22s %s\n", $n, luhn_valid($n) ? "valid" : "invalid";
}

for my $p ("7992739871", "453201511283036", "12345") {
    my $c = check_digit($p);
    say "$p -> $p$c ", luhn_valid("$p$c") ? "(valid)" : "(BROKEN)";
}

my $good = "79927398713";
my ($caught, $missed) = (0, 0);
for my $pos (0 .. length($good) - 1) {
    for my $d (0 .. 9) {
        next if $d == substr($good, $pos, 1);
        my $typo = substr($good, 0, $pos) . $d . substr($good, $pos + 1);
        if (luhn_valid($typo)) { $missed++ } else { $caught++ }
    }
}
say "single-digit typos caught: $caught, missed: $missed";
