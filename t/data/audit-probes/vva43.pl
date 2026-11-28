$_ = 1; sub f { local $_ = 9; g() } sub g { $_ } print f(), "$_\n";
