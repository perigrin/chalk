my @m; $m[$_][$_] = 1 for 0..2; print join(",", map { scalar @$_ } @m), "\n";
