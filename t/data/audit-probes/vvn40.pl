my @r; my $i = 0; while ($i < 3) { my $x = $i++; $x *= 2; push @r, \$x } print join(",", map { $$_ } @r), "\n";
