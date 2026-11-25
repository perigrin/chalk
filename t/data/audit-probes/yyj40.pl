our @a=(1,2,3); sub g1 { "@a" } sub t { local $a[1] = 9; g1() } print t(), g1(), "\n";
