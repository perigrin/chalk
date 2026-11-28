our @a = (1,2,3); { local $a[1] = 8; print "@a;" } print "@a\n";
