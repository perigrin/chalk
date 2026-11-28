our $x = 1; sub f { ${*x{SCALAR}} = 5; $_[0] } print f($x), "\n";
