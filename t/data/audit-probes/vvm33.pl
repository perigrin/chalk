our @a = (1,2,3); sub f { local @a = @a; pop @a; "@a" } print f(), "|@a\n";
