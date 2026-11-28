my ($x, $y) = (1, 2); sub d { die "x\n" } eval { ($x, $y) = (5, d()) }; print "$x$y\n";
