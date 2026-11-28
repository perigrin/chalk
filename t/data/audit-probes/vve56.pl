my $x = 1; sub f { my $l = pop; $_[0] += $l } f($x, 4); print "$x\n";
