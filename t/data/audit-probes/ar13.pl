sub f { shift; $_[0] = 3 } my ($x, $y) = (1, 2); f($x, $y); print "$x $y\n";
