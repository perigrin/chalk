sub f { my @a = (3,4); my $s = 0; for (@a) { $_ *= 2; $s += $_ } print "$s|@a\n" } f();
