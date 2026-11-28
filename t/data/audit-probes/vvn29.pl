my @r; for my $i (1..2) { for my $j (1..2) { $j += $i * 10; push @r, \$j } } print join(",", map { $$_ } @r), "\n";
