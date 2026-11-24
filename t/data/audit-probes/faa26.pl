my @a=(1,2,3); sub f { shift; $_[0]=0 } f(@a); print "@a\n";
