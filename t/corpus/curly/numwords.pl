# Numbers in English words, up to the trillions, and back again for the
# small ones; the letter counts of 1 to 1000, as in Project Euler 17.
use v5.42;

# No int yet (step 22): whole-number division of non-negative numbers.
sub idiv ($n, $d) { ($n - $n % $d) / $d }

my @ones = qw(zero one two three four five six seven eight nine ten eleven twelve
              thirteen fourteen fifteen sixteen seventeen eighteen nineteen);
my @tens = qw(_ _ twenty thirty forty fifty sixty seventy eighty ninety);
my @scales = ([1_000_000_000_000, "trillion"], [1_000_000_000, "billion"], [1_000_000, "million"], [1000, "thousand"]);

sub below_thousand ($n) {
    my @parts;
    if ($n >= 100) {
        push @parts, $ones[idiv($n, 100)] . " hundred";
        $n %= 100;
        push @parts, "and" if $n;
    }
    if ($n >= 20) {
        push @parts, $tens[idiv($n, 10)] . ($n % 10 ? "-" . $ones[$n % 10] : "");
    } elsif ($n > 0) {
        push @parts, $ones[$n];
    }
    return join " ", @parts;
}

sub words ($n) {
    return "minus " . words(-$n) if $n < 0;
    return "zero" if $n == 0;
    my @parts;
    for my $s (@scales) {
        my ($size, $name) = $s->@*;
        if ($n >= $size) {
            push @parts, below_thousand(idiv($n, $size)) . " $name";
            $n %= $size;
        }
    }
    push @parts, ($n < 100 && @parts ? "and " : "") . below_thousand($n) if $n;
    return join(" ", @parts);
}

my %value;
$value{$ones[$_]} = $_ for 0 .. 19;
$value{$tens[$_]} = 10 * $_ for 2 .. 9;

sub from_words ($s) {
    my ($total, $current) = (0, 0);
    my @words;
    my $w = "";
    for my $i (0 .. length($s)) {
        my $c = substr($s, $i, 1);
        if ($c ne "" && $c ne " " && $c ne "-") { $w .= $c; next }
        push @words, $w if length $w;
        $w = "";
    }
    for my $w (@words) {
        next if $w eq 'and';
        if ($w eq 'hundred') { $current *= 100 }
        elsif ($w eq 'thousand') { $total += $current * 1000; $current = 0 }
        else { $current += $value{$w} // die "unknown word '$w'\n" }
    }
    return $total + $current;
}

for my $n (0, 7, 13, 21, 99, 100, 101, 342, 1000, 1001, 12345, 1_000_000, 7_000_005, 123_456_789_012, -40) {
    say "$n: ", words($n);
}

my $bad = 0;
for my $n (1 .. 9999) {
    $bad++ unless from_words(words($n)) == $n;
}
say "round trips that failed below 10,000: $bad";

my $letters = 0;
for my $n (1 .. 1000) {
    my $w = words($n);
    $letters += grep { my $c = substr($w, $_, 1); $c ne ' ' && $c ne '-' } 0 .. length($w) - 1;
}
say "letters used writing 1 to 1000: $letters";
