our @a = (1,2,3); sub ad { push @a, @_ } sub f { local @a; ad(8); ad(9); "@a" } print f(), "|@a\n";
