my @a = (1, 2); sub f { $_[1] = 9 } f(reverse @a); print "@a\n";
