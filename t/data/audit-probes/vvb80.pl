my @r; for my $i (1..2) { my $x = $i; push @r, \$x for 1..2 } ${$r[0]} = 9; print join(",", map { $$_ } @r), "\n";
