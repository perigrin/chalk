# Calendars: the day of the week by Zeller's congruence, leap years, a
# month printed as cal(1) prints it, the days between two dates, and
# the Friday the 13ths of a year.
use v5.42;

# No int yet (step 22): whole-number division of non-negative numbers.
sub idiv ($n, $d) { ($n - $n % $d) / $d }

my @month_names = qw(January February March April May June July August September October November December);
my @day_names = qw(Saturday Sunday Monday Tuesday Wednesday Thursday Friday);

sub is_leap ($y) { ($y % 4 == 0 && $y % 100 != 0) || $y % 400 == 0 }

sub days_in ($y, $m) {
    return 29 if $m == 2 && is_leap($y);
    return (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[$m - 1];
}

# 0 is Saturday
sub zeller ($y, $m, $d) {
    if ($m < 3) { $m += 12; $y-- }
    my $k = $y % 100;
    my $j = idiv($y, 100);
    return ($d + idiv(13 * ($m + 1), 5) + $k + idiv($k, 4) + idiv($j, 4) + 5 * $j) % 7;
}

sub print_month ($y, $m) {
    my $title = $month_names[$m - 1] . " $y";
    say " " x idiv((20 - length $title), 2), $title;
    say "Su Mo Tu We Th Fr Sa";
    my $first = (zeller($y, $m, 1) + 6) % 7;
    my @cells = (("  ") x $first, map { sprintf "%2d", $_ } 1 .. days_in($y, $m));
    while (@cells) {
        say join(" ", splice(@cells, 0, 7));
    }
}

sub day_number ($y, $m, $d) {
    my $n = $d;
    $n += days_in($y, $_) for 1 .. $m - 1;
    $n += is_leap($_) ? 366 : 365 for 1 .. $y - 1;
    return $n;
}

for my $date ([2000, 1, 1], [1969, 7, 20], [2026, 11, 27], [1900, 3, 1], [2024, 2, 29]) {
    my ($y, $m, $d) = $date->@*;
    printf "%04d-%02d-%02d was a %s\n", $y, $m, $d, $day_names[zeller($y, $m, $d)];
}

print_month(2026, 11);
print "\n";
print_month(2024, 2);

my $between = day_number(2026, 11, 27) - day_number(1969, 7, 20);
say "days from the moon landing to today: $between";
my $leaps = grep { is_leap($_) } 1901 .. 2000;
say "leap years in the twentieth century: $leaps";
my @f13 = grep { zeller(2026, $_, 13) == 6 } 1 .. 12;
say "Friday the 13ths in 2026: ", join(", ", map { $month_names[$_ - 1] } @f13);
