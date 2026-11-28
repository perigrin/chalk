our $x = 1; sub f { local $x = 2; $x } print f(), $x, "\n";
