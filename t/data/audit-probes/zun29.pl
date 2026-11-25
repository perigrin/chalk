my @a; eval { push @a,1; die "x\n"; push @a,2 }; print "@a\n";
