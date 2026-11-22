my @a=(1,2); my @b = map { $_ * 2 } @a; @a = (); print "@b\n";
