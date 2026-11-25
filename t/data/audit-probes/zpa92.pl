my $x=1; sub f { $_[0]+=1 for 1..3 } f($x); print "$x\n";
