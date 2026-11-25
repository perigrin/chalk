use feature 'state'; sub c { state @a; push @a, scalar @a; "@a" } c(); print c(), "\n";
