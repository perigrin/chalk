my $x = 1; sub f { $_[0] = 9 } f($x + 0); f("$x"); f(-$x); print "$x\n";
