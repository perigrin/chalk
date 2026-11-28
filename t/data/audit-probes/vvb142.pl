my @a = (1,2,3); sub f { $_[0] *= 2 } f($_) for @a; print "@a\n";
