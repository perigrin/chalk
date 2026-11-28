our $x = 1; sub g { $_[0] = 5 } sub f { g($_[0]); $x } print f($x), "\n";
