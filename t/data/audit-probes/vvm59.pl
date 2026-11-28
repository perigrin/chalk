our @a = (1,2,3); sub cnt { scalar @a } sub f { local @a = (5); push @a, 6; cnt() } print f(), cnt(), "\n";
