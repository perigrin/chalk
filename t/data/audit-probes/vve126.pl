our @a = (1,2); sub c { $a[0] = 5; 2 } sub f { "@_" } print f(@a, c()), "\n";
