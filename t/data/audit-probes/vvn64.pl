my @r; for my $i (1..3) { push @r, (\$i) x 2 } ${$r[2]} = 9; print join(",", map { $$_ } @r), "\n";
