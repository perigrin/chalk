our @a = (1,2,3); { local @a = grep { $_ > 1 } @a; print "@a;" } print "@a\n";
