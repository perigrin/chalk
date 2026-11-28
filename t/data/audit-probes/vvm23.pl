our @a = (1,2,3); { local @a = @a; push @a, 8; print "@a;" } print "@a\n";
