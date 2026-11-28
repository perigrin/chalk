my @r; for my $i (1..3) { my $x = $i; push @r, \$x; $x *= 2 } print join(",", map { $$_ } @r), "\n";
