our ($x,$y)=(1,2); sub f { local ($x,$y) = (8,9); g() } sub g { "$x$y" } print f(), "$x$y\n";
