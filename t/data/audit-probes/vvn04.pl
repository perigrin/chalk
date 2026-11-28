my @r; for my $i (1..3) { push @r, \$i; $i *= 2 } print join(",", map { $$_ } @r), "\n";
