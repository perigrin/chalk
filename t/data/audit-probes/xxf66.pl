$_ = "t"; sub f { $_ = "c" } for (1..2) { f() } print "$_\n";
