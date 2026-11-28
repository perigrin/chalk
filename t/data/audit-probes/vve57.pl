my $x = 1; sub f { @_ = (9); $_[0]++ } f($x); print "$x\n";
