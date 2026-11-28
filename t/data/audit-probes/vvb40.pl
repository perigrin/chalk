my ($lo, $hi) = (1, 3); my @r; for my $i ($lo..$hi) { push @r, \$i } print join(",", map { $$_ } @r), "\n";
