my @r; for my $i (1..2) { my $x = $i; my $k = 0; while ($k++ < 2) { push @r, \$x } } ${$r[0]} = 9; print join(",", map { $$_ } @r), "\n";
