my @a; sub f { print "f"; 0 } sub g { print "g"; 1 } $a[f()] = g(); print "\n";
