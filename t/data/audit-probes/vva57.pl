our @a = (1,2); { local @a; print scalar(@a); push @a, 5 } print "@a\n";
