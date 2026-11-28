our @a = (1,2,3); sub f { local @a = @a[0,1]; push @a, 9; "@a" } print f(), "|@a\n";
