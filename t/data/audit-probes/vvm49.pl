our @a = (1,2,3); { local @a = (7); @a = (8, 9); } print "@a\n";
