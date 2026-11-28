my @a = (1,2,3); sub f { $_ *= 2 for @_ } f(@a); print "@a\n";
