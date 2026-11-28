my ($x, $y) = (1, 2); sub f { $_[0] = 9 } f(do { $x }); print "$x$y\n";
