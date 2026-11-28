our $x = 1; sub c { local $x = 5; 2 } sub f { $_[0] } print f($x, c()), "\n";
