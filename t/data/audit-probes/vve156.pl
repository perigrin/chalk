my @a; sub f { $_[0] = 9 } f($a[3]); print scalar(@a), "\n";
