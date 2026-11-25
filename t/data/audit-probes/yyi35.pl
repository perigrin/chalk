sub set { $_ = "s" for @_ } my ($x,@a)=(1,2,3); set($x,@a); print "$x@a\n";
