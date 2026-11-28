our @a = (1,2,3); { local @a = @a[0,1]; print "@a;" } print "@a\n";
