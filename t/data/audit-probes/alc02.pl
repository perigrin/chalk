our $x=1; sub g { $_[0] } sub f { $x=5; g($_[0]) } print f($x),"\n";
