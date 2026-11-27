our $g = 1; sub f { local $g = 5 if $_[0]; $g } print f(1), f(0), $g, "\n";
