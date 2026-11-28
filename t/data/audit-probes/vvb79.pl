my @r; for my $i (1..2) { my $x = $i; for my $j (1..2) { push @r, \$x } } ${$r[0]} = 9; print join(",", map { $$_ } @r), "\n";
