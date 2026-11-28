our $x = 1; sub f { local $x = $x * 2; $_[0] ? f($_[0]-1) : $x } print f(3), $x, "\n";
