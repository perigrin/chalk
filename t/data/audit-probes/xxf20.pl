our $g = 1; sub f { local $g = 2; $_[0] } print f($g), "\n";
