my @a=(1,2,3); sub f { $_[1]=0 } f(@a); print "@a\n";
