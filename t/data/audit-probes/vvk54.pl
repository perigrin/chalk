my @a = (1, 2); sub f { $_ * 2 } my @l = map { f() } @a; print "@l\n";
