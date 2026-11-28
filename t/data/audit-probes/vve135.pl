my ($x, $y) = (1, 2); sub f { $_[0] = 9 } f(1 ? $x : $y); print "$x$y\n";
