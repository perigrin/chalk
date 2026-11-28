sub f { 1 } sub h { 2 } { no warnings; *f = \&h; } print f(), "\n";
