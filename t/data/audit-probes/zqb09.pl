our $x=1; sub f { local $x=5; g2($_[0]) } sub g2 { $_[0]=7; $x } print f($x), $x, "\n";
