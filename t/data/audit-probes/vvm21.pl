our @a = (1,2,3); { local @a = (7); push @a, 8 } print "@a\n";
