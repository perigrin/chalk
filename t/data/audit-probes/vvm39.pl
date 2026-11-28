our @a = (1,2,3); eval { local @a = (7); push @a, 8; die "x\n" }; print "@a\n";
