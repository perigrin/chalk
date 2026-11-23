sub f { my @a = (1,2); my $r = \@a; my $s=""; for my $x (@a) { $x .= "y"; $r->[0] = "q"; $s .= $x } print "$s|@a\n" } f();
