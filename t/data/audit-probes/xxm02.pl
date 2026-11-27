my @r; for (1..3) { push @r, \$_ } print join(",", map { $$_ } @r), "\n";
