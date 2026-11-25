sub f { print "f"; 1 } sub g { print "g"; 2 } sub h { "@_" } print h(g(), f(), g()), "\n";
