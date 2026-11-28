our $x = 1; sub r { $x } sub f { local $x = 2; r() } print f(), r(), "\n";
