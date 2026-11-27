our @g = (1,2,3); sub f { local @g[1,2] = (0,0); "@g" } print f(), "@g\n";
