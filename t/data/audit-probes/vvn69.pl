my @r; sub lp { my $n = shift; for my $i (1..$n) { push @r, \$i; lp($n - 1) } } lp(2); print join(",", map { $$_ } @r), "\n";
