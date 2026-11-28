our @a = (1,2,3); sub j { "@a" } sub f { local $" = ","; j() } print f(), j(), "\n";
