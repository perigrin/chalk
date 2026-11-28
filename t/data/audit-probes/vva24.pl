my @a = (1,2,3); { local $a[0] = 8; print "@a;" } print "@a\n";
