my @a = (1, 2); sub f { $_[1] = 9 } f(grep { 1 } @a); print "@a\n";
