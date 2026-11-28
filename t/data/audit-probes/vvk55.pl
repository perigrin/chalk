my @a = (1, 2); sub f { $_ = 0 } map { f() } @a; print "@a\n";
