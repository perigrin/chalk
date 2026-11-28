# A sales report: records in an array of hashes, grouped and totalled by
# region and by quarter, printed with printf in aligned columns, with
# percentages, a ranking, and a small bar chart.
use v5.42;

my @sales = map { +{ region => $_->[0], rep => $_->[1], quarter => $_->[2], amount => $_->[3] } } (
    ["North", "Ann", 1, 12500.50], ["North", "Ann", 2, 13200], ["North", "Bob", 1, 9800.25], ["North", "Bob", 2, 11050],
    ["South", "Cid", 1, 15300], ["South", "Cid", 2, 14100.75], ["South", "Dee", 1, 7200], ["South", "Dee", 2, 8800.10],
    ["East", "Eve", 1, 10400], ["East", "Eve", 2, 12950.40], ["West", "Fay", 1, 5300], ["West", "Fay", 2, 6100],
);

my %by_region;
my %by_quarter;
my %by_rep;
my $grand;
for my $s (@sales) {
    $by_region{$s->{region}} += $s->{amount};
    $by_quarter{$s->{quarter}} += $s->{amount};
    $by_rep{$s->{rep}} += $s->{amount};
    $grand += $s->{amount};
}

my $line = "-" x 44;
printf "%-8s %12s %12s %8s\n", "Region", "Q1", "Q2", "Share";
say $line;
for my $region (sort { $by_region{$b} <=> $by_region{$a} } keys %by_region) {
    my %q;
    $q{$_->{quarter}} += $_->{amount} for grep { $_->{region} eq $region } @sales;
    printf "%-8s %12.2f %12.2f %7.1f%%\n", $region, $q{1}, $q{2}, 100 * $by_region{$region} / $grand;
}
say $line;
printf "%-8s %12.2f %12.2f %7.1f%%\n", "Total", $by_quarter{1}, $by_quarter{2}, 100;
printf "%-8s %25.2f\n", "Grand", $grand;
print "\n";

my $rank = 0;
for my $rep (sort { $by_rep{$b} <=> $by_rep{$a} || $a cmp $b } keys %by_rep) {
    $rank++;
    my $bar = "*" x ($by_rep{$rep} / 1000);
    printf "%2d. %-4s %10s %s\n", $rank, $rep, commify(sprintf "%.2f", $by_rep{$rep}), $bar;
}

sub commify ($n) {
    my $dot = index($n, ".");
    my $whole = $dot < 0 ? $n : substr($n, 0, $dot);
    my $frac = $dot < 0 ? undef : substr($n, $dot + 1);
    my $out = "";
    while (length $whole > 3) {
        $out = "," . substr($whole, -3) . $out;
        $whole = substr($whole, 0, length($whole) - 3);
    }
    return $whole . $out . (defined $frac ? ".$frac" : "");
}

my $growth = ($by_quarter{2} - $by_quarter{1}) / $by_quarter{1};
printf "\nQ2 over Q1: %+.1f%%\n", 100 * $growth;
printf "best single quarter: %s\n", join(" ", map { sprintf "%s/Q%d", $_->{rep}, $_->{quarter} } (sort { $b->{amount} <=> $a->{amount} } @sales)[0 .. 2]);
