my @a = (1,2,3); sub f { $_ .= "x" } for (@a) { f() } print "@a\n";
