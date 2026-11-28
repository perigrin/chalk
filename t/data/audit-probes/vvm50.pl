our @a = (1,2,3); { local @a = (7); undef @a; } print "@a\n";
