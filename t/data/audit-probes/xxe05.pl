our $x = 1; sub f { $x } { local *x = \7; print f() } print f(), "\n";
