my @r; for my $i (1..3) { my $x = $i; my $c = \$x; $$c++; push @r, $c } ${$r[0]}++; print join(",", map { $$_ } @r), "\n";
