our $x = 1; sub f { *x = \7; $x } print f($x), "$x\n";
