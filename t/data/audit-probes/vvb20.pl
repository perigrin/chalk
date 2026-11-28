my @r; my $n = 0; for my $i (1..2) { my $x = $i; push @r, \$x; redo if ++$n == 1 } print join(",", map { $$_ } @r), "\n";
