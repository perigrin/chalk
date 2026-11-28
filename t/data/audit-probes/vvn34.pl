my @r; for (1..3) { $_ *= 2; push @r, \$_ } print join(",", map { $$_ } @r), "\n";
