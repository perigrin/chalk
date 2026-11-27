my @r; my $n = 0; while ($n < 3) { my $x = $n++; push @r, \$x } print join(",", map { $$_ } @r), "\n";
