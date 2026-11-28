sub f { @_ = (7, 8); "@_" } my ($x, $y) = (1, 2); print f($x, $y), "$x$y\n";
