my $x=1; sub f { $_[0]=5 if $_[1] } f($x,0); print $x; f($x,1); print "$x\n";
