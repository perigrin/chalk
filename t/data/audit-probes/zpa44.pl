my $x=1; sub f { goto &g } sub g { $_[0]=3 } f($x); print "$x\n";
