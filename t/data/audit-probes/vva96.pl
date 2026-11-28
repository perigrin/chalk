our @a = (1,2,3); sub f { local $a[0] = 9; g() } sub g { "@a" } print f(), g(), "\n";
