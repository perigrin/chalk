our @a = (1,2,3); { local @a = ($a[2]); print "@a;" } print "@a\n";
