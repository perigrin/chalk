my ($x, $y) = (1, 2); my @r = \($x, $y); ${$r[1]} = 9; print "$x$y\n";
