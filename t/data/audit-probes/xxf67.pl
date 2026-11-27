$_ = "t"; sub f { $_ = "c" } my @a = (1,2); for (@a) { f() } print "$_@a\n";
