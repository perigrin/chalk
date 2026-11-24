our @l; eval { push @l,1; die "a\n" }; eval { push @l,2 }; print "@l\n";
