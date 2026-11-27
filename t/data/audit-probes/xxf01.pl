our $g = 1; sub rd { $g } sub f { local $g = 2; rd() } print f(), rd(), "\n";
