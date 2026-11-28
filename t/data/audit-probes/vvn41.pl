my @r; my $i = 0; while ($i < 3) { my $x = $i++; push @r, \$x; $x += 10 } print join(",", map { $$_ } @r), "\n";
