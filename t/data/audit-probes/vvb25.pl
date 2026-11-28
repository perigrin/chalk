my @r; for my $i (1..3) { my $x; $x += $i; push @r, \$x } print join(",", map { $$_ } @r), "\n";
