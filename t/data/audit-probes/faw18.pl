our ($u,$v)=(1,2); sub f { local ($u,$v)=(8,9); g() } sub g { "$u$v" } print f(), g(), "\n";
