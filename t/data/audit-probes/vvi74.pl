my @a = ("ab", "cd"); my @b = map { s/[ac]/z/; $_ } @a; print "@a|@b\n";
