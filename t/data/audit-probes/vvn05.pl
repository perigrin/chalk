my @r; for my $i (1..3) { $i = 9; push @r, \$i } print join(",", map { $$_ } @r), "\n";
