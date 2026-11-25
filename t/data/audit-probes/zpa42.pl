my $x=1; sub f { $_[0]=2; &g } sub g { $_[0]=3 } f($x); print "$x\n";
