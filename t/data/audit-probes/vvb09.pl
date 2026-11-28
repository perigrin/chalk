my @r; my $i = 0; until ($i >= 3) { my $j = $i++; push @r, \$j } print join(",", map { $$_ } @r), "\n";
