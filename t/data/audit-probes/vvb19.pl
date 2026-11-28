my @r; for my $i (1..3) { push @r, \$i; last if $i == 2 } print join(",", map { $$_ } @r), "\n";
