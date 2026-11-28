our $x = 1; sub g { $_[0] = 5 } sub f { g($x); $_[0] } print f($x), "\n";
