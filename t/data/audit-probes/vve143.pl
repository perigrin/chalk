my ($x, $y) = (1, 2); sub f { $_[1] = 9 } f(($x, $y)); print "$x$y\n";
