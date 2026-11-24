our @a=(1,2,3); sub f { local $a[1]=9; die "x\n" } eval { f() }; print "@a\n";
