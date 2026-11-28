our @a = (1,2,3); { local @a = (7); $_++ for @a; print "@a;" } print "@a\n";
