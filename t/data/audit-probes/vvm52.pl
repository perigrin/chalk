our @a = (1,2,3); { local @a = (7); splice(@a, 0, 1, 5, 6); print "@a;" } print "@a\n";
