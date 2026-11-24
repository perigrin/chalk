our $x=1; sub g { $x=2 } sub f { g(); $_[0] } print f($x),"\n";
