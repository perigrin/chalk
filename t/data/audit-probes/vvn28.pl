my @r; for my $i (1..3) { if ($i > 1) { $i *= 2 } push @r, \$i } print join(",", map { $$_ } @r), "\n";
