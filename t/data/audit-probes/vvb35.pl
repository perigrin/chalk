my @r; my $x; for my $i (1..3) { $x = $i; push @r, \$x } print join(",", map { $$_ } @r), "\n";
