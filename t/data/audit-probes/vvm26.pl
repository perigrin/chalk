our @a = (1,2,3); { local @a = reverse @a; print "@a;" } print "@a\n";
