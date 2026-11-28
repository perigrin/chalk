our @a = (1,2,3); { local @a = @a[0,1]; push @a, 9; print "@a;" } print "@a\n";
