my @r; for my $i (1..3) { my $x = do { my $y = $i * 2; \$y }; push @r, $x } print join(",", map { $$_ } @r), "\n";
