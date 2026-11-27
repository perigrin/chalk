our $x = 1; sub c { $x = 3; 2 } sub id { "@_" } print id($x, c()), "\n";
