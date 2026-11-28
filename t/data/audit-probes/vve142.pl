my ($x, $y) = (1, 2); sub f { $_[0] = 9 } f(scalar($x)); print "$x$y\n";
