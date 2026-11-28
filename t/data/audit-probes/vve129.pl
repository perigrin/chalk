my $x = 1; sub f { $_[0] = 9 } f(my $y = $x); print "$x$y\n";
