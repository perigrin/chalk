my @a=(1,2,3); my $i=0; sub f { $i=2; $_[0]=9 } f($a[$i]); print "@a\n";
