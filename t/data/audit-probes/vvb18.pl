my @r; for my $i (1..3) { next if $i == 2; push @r, \$i } print join(",", map { $$_ } @r), "\n";
