my @r; for my $i (1..3) { $i += 10 if $i == 2; push @r, \$i } print join(",", map { $$_ } @r), "\n";
