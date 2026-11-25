our @a=(1,2); eval { local @a=(7); die "x\n" }; print "@a\n";
