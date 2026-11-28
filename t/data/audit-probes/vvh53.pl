my @l; eval { push @l, 1; eval { push @l, 2; die "a\n" }; push @l, 3; die "b\n"; push @l, 4 }; push @l, 5; print "@l\n";
