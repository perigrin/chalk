my @r; for my $i (reverse 1..3) { push @r, \$i } print join(",", map { $$_ } @r), "\n";
