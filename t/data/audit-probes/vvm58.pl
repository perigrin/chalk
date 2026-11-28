our @a = (1,2,3); sub f { local @a = (5); my @c = @a; push @a, 6; "@c" } print f(), "|@a\n";
