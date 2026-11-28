my ($x, $y) = (1, 2); my ($p, $q) = \($x, $y); $$p = 9; print "$x$y\n";
