our $x = 1; sub f :lvalue { $x } sub g { local $x = 2; f() = 5; $x } print g(), "$x\n";
