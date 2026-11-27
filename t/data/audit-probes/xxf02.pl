our $g = 1; sub rd { $g } sub f { local $g = $g + 1; rd() } print f(), f(), rd(), "\n";
