my @r; for (1..3) { push @r, \$_; $_ *= 2 } print join(",", map { $$_ } @r), "\n";
