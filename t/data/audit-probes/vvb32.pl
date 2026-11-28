my @r; for my $i (1..3) { my $x = $i; my $y = \$x; push @r, $y } ${$r[1]} = 9; print join(",", map { $$_ } @r), "\n";
