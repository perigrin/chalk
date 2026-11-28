our $x = 1; sub f { no strict 'refs'; local ${"x"} = 2; g() } sub g { $x } print f(), g(), "\n";
