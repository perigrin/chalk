our $x = 1; sub f { ${"x"} = 5; $_[0] } print f($x), "\n";
