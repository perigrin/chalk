my @a=(1); sub d { die "x\n" } eval { push @a, 2, d() }; print "@a\n";
