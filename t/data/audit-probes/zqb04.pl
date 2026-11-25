our $x=1; sub f { local $x; $_[0] } print f($x), "\n";
