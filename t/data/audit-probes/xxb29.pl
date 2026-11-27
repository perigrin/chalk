my @a=(1,2,3); my @b = map { $a[$#a] = 0; $_ } @a; print "@a|@b\n";
