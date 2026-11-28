my @r; for my $i (1..3) { my $n = 0; while ($n++ < 2) { $i++ } push @r, \$i } print join(",", map { $$_ } @r), "\n";
