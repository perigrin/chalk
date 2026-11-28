my @r; for my $i (1..3) { my ($x, $y) = ($i, $i * 2); push @r, \$x, \$y } print join(",", map { $$_ } @r), "\n";
