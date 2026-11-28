my @r; my $n = 0; for my $i (1..2) { push @r, \$i; redo if ++$n == 1 } print join(",", map { $$_ } @r), "\n";
