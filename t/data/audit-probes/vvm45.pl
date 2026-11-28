our @a = (1,2,3); { local @a = (3); local @a = (4); print "@a;" } print "@a\n";
