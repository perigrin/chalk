my @a = (1,2); sub d { die "x\n" } eval { $a[0] = d() }; eval { $a[d()] = 5 }; print "@a\n";
