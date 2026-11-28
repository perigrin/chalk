my ($x, $y) = (1, 2); sub d { die "x\n" } eval { $x = 5; $y = d(); }; print "$x$y\n";
