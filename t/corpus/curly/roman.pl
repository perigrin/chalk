# Roman numerals both ways, checked for every number from 1 to 3999,
# with the years of a few events and some arithmetic done in Roman.
use v5.42;

my @table = (
    [1000, 'M'], [900, 'CM'], [500, 'D'], [400, 'CD'],
    [100,  'C'], [90,  'XC'], [50,  'L'], [40,  'XL'],
    [10,   'X'], [9,   'IX'], [5,   'V'], [4,   'IV'],
    [1,    'I'],
);
my %value = (I => 1, V => 5, X => 10, L => 50, C => 100, D => 500, M => 1000);

sub to_roman ($n) {
    die "out of range: $n\n" if $n < 1 || $n > 3999;
    my $out = '';
    for my $pair (@table) {
        my ($v, $r) = $pair->@*;
        while ($n >= $v) {
            $out .= $r;
            $n -= $v;
        }
    }
    return $out;
}

sub from_roman ($s) {
    my $total = 0;
    my $u = uc $s;
    my @chars = map { substr($u, $_, 1) } 0 .. length($u) - 1;
    for my $i (0 .. $#chars) {
        my $v = $value{$chars[$i]} // die "not a roman digit: $chars[$i]\n";
        my $next = $i < $#chars ? ($value{$chars[$i + 1]} // 0) : 0;
        $total += $v < $next ? -$v : $v;
    }
    return $total;
}

for my $n (1, 4, 9, 14, 40, 90, 400, 1994, 2026, 3999) {
    printf "%4d = %s\n", $n, to_roman($n);
}

my $bad = 0;
my $longest = '';
for my $n (1 .. 3999) {
    my $r = to_roman($n);
    $bad++ unless from_roman($r) == $n;
    $longest = $r if length $r > length $longest;
}
say "round trips that failed: $bad";
say "the longest numeral is $longest (", from_roman($longest), ")";

my %events = (MCMLXIX => "the moon landing", MDCCLXXVI => "a declaration", MMXXVI => "this program");
for my $r (sort { from_roman($a) <=> from_roman($b) } keys %events) {
    say "$r (", from_roman($r), "): $events{$r}";
}

say "XLII + XIX = ", to_roman(from_roman("XLII") + from_roman("XIX"));
say "MMXXVI - MCMLXIX = ", to_roman(from_roman("MMXXVI") - from_roman("MCMLXIX"));

for my $bad_input ("MMXQ", "0") {
    try { from_roman($bad_input) } catch ($e) { print "from_roman($bad_input): $e" }
}
try { to_roman(4000) } catch ($e) { print "to_roman(4000): $e" }
