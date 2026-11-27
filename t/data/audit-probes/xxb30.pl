my @a=(1,2,3); my @b = grep { $a[2] = 0; $_ } @a; print "@a|@b\n";
