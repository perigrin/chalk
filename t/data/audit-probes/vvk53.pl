my @a = (1, 2); sub f { $_++ } for (@a) { f() } print "@a\n";
