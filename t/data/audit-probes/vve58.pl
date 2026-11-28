my $x = 1; sub f { unshift @_, 0; $_[1]++ } f($x); print "$x\n";
