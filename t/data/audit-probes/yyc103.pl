sub f { print "f"; 1 } sub g { print "g"; 2 } my ($p,$q) = (f(), g()); print "$p$q\n";
