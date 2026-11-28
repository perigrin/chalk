my @r; my ($lo, $hi) = (1, 3); for my $i ($lo..$hi) { $i *= 2; push @r, \$i } print join(",", map { $$_ } @r), "\n";
