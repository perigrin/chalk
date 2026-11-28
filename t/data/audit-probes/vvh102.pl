my ($x, $y) = (1, 2); eval { ($x, $y) = (5, die "x\n") }; print "$x$y\n";
