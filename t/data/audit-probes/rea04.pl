our $g=1; sub f { local $g = 5; g() } sub g { $g } print f(), " $g\n";
