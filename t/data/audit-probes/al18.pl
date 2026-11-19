my @a = (1,2,3); my @b = map { $_ * 2 } @a; s/1/x/ for @a; print "@a @b\n";
