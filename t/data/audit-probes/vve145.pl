my @a = (1, 2); sub f { $_[1] = 9 } f(@a[0,1]); print "@a\n";
