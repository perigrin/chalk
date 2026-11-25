sub f { eval { return "in" }; "out" } sub g { my @r = eval { return (1,2) }; scalar(@r) } print f(), g(), "\n";
