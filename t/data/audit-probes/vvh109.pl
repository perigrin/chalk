my @a; sub d { die "x\n" } eval { push @a, 1, d() }; print scalar(@a), "\n";
