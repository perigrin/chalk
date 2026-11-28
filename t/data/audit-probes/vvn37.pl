my @r; for my $i (1..3) { my $x = $i; $x *= 2; push @r, \$x } print join(",", map { $$_ } @r), "\n";
