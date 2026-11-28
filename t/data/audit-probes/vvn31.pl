my @r; for my $i (1..2) { for my $j (1..2) { $i++; push @r, \$i } } print join(",", map { $$_ } @r), "\n";
