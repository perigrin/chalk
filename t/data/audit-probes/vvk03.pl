sub f { for (@_) { $_ *= 2 } } my ($x, $y) = (1, 2); f($x, $y); print "$x$y\n";
