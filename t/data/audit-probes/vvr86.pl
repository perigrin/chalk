my @a = (1,2,3); my @b = @a[1..$#a]; $_ *= 2 for @b; print "@a|@b\n";
