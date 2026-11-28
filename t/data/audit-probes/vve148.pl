my @a = (2, 1); sub f { $_[1] = 9 } f(sort { $a <=> $b } @a); print "@a\n";
