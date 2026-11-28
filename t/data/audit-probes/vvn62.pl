my @r; for my $i (1..3) { push @r, \$i unless @r > 1 } print join(",", map { $$_ } @r), "\n";
