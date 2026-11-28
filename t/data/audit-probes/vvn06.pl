my @r; for my $i (1..3) { $i .= "a"; push @r, \$i } print join(",", map { $$_ } @r), "\n";
