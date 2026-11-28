my @r; for my $i (1..3) { $i++ for 1..2; push @r, \$i } print join(",", map { $$_ } @r), "\n";
