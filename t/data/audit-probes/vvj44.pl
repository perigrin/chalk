my @a = (1,2,3); my @b = map { $_ } @a; $_ = 0 for @b; print "@a\n";
