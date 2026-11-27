our @g = (1,2,3); sub rd { "@g" } sub f { local $g[0] = 7; rd() } print f(), rd(), "\n";
