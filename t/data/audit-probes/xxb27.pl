my @a=("ab","cd"); my @b = map { s/a/X/; $_ } @a; print "@a|@b\n";
