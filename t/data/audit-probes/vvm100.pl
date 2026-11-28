our $x = 1; sub f { no strict 'refs'; local ${$_[0]} = 2; g() } sub g { $x } print f("x"), g(), "\n";
