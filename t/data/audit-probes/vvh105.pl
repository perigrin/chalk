my ($x, $y) = (1, 2); sub d { $x = 7; die "x\n" } eval { $y = $x + d(); }; print "$x$y\n";
