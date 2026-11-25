sub f { print "f"; 0 } sub g { print "g"; 1 } my @a=(5,6); @a[f(), g()] = (g(), f()); print " @a\n";
