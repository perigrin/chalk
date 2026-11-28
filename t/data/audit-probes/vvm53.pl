our @a = (1,2,3); { local @a = (7); unshift @a, 6; print "@a;" } print "@a\n";
