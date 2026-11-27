my @a = (1,2); { local $a[0] = 9; print "@a" } print "@a\n";
