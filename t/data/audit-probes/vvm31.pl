our @a = (1,2,3); { local @a = (scalar(@a)); print "@a;" } print "@a\n";
