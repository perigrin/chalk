my @r; for my $i (1..3) { my $x; push @r, \$x; $x = $i } print join(",", map { $$_ } @r), "\n";
