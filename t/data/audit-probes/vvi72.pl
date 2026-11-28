my @a = ("ab", "cd"); my @b = map { s/[ac]/z/r } @a; print "@a|@b\n";
