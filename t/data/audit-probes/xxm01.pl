my @r; for my $i (1,2,3) { push @r, \$i } print join(",", map { $$_ } @r), "\n";
