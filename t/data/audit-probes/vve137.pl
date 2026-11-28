my ($x, $y) = (0, 2); sub f { $_[0] = 9 } f($x || $y); print "$x$y\n";
