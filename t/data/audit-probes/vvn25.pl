my @r; for my $i (1..3) { ($i, my $t) = ($i + 4, 0); push @r, \$i } print join(",", map { $$_ } @r), "\n";
