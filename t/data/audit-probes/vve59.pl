my $x = 1; sub f { push @_, 0; $_[0]++ } f($x); print "$x\n";
