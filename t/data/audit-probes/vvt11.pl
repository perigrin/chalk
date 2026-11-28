my @a = (1,2,3); sub f { $_[0] .= "x" } f($_) for @a; f($a[0]); print "@a\n";
