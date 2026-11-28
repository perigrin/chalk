my @r; for my $i (1..3) { push @r, \$i, \$i } ${$r[0]} = 9; print join(",", map { $$_ } @r), "\n";
