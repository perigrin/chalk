our $x=1; sub f { local $x=2; $_[0] } print f($x),"\n";
