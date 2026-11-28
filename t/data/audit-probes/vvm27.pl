our @a = (1,2,3); { local @a = map { $_ * 2 } @a; print "@a;" } print "@a\n";
