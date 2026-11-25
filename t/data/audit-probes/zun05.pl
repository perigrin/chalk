our @a=(1,2); eval { local $a[1]=9; die "x\n" }; print "@a\n";
