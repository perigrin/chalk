our @a = (1,2,3); { local $a[0] = 9; @a = (4,5,6); print "@a;" } print "@a\n";
