our $x=1; sub f { local $x=5; $_[0] } print f($x),"\n";
