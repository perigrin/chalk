my @r; my $i = 0; while ($i < 3) { my $x = $i++; my $q = \$x; push @r, $q; $$q += 10; $x++ } print join(",", map { $$_ } @r), "\n";
