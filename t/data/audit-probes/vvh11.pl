my @a = (1); eval { push @a, 2; die "z\n"; push @a, 3 }; print "@a\n";
