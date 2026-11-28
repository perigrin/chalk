our @a = (1,2,3); { local @a = (7); $a[3] = 1; print scalar(@a), ";" } print "@a\n";
