our $g = 1; sub f { local $g = 2; $_[0] = 9; $g } print f($g), $g, "\n";
