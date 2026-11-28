our @a = (1,2,3); { local $a[0] = 9; shift @a; print "@a;" } print "@a\n";
