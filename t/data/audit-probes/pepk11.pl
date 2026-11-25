our $x=1; sub f { local $x=2; $_[0]=7; $x } print f($x), $x, "\n";
