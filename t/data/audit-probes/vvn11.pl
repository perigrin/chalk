my @r; for my $i (1..3) { push @r, \$i } $$_ *= 2 for @r; print join(",", map { $$_ } @r), "\n";
