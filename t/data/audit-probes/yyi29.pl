sub set { $_[1] = "s" } my ($x,$y)=(1,2); set($x,$y); set(my @a = (1,2)); print "$x$y@a\n";
