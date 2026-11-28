my @r; sub lp { for my $i (1..2) { push @r, \$i } } lp(); lp(); ${$r[0]} = 9; print join(",", map { $$_ } @r), "\n";
