our @a = (1,2,3); { local @a = (@a, 4); print "@a;" } print "@a\n";
