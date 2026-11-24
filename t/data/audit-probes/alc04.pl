our $x=1; sub g { $x=3 } sub f { g(); $_[0] + $_[1] } print f($x,$x),"\n";
