my @a=(undef,2); for (@a) { $_ //= 5 } print "@a\n";
