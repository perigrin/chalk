our @a = (1,2,3); sub ad { push @a, @_ } { local @a = (7); ad(8); print "@a;" } print "@a\n";
