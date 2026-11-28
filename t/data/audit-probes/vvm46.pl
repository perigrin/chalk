our @a = (1,2,3); { local @a = (3); { local @a = (4); push @a, 5 } print "@a;" } print "@a\n";
