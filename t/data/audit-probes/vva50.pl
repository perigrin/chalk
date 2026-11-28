our $x = 1; sub f { $_[0] } { local $x = 2; print f($x) } print f($x), "\n";
