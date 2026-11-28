my @a; sub d { die "x\n" } eval { @a = (1, d()) }; print scalar(@a), "\n";
