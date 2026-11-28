my @r; for (my $i = 0; $i < 3; $i++) { push @r, \$i } print join(",", map { $$_ } @r), "\n";
