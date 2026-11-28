our @a = (1,2,3); { local @a = (7); $#a = -1; } print "@a\n";
