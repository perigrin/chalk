my $x=1; sub f { $_[0]=5 } f($x) for 1..2; my $y=$x+1; print "$y\n";
