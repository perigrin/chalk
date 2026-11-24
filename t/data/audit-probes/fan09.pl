my @a=(1,2); eval { map { $_++; die "x\n" if $_==3 } @a }; print "@a\n";
