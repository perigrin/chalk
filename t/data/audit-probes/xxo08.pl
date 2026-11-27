my @a = (1,2,3); { local @a[0,1] = (8,9); print "@a" } print "@a\n";
