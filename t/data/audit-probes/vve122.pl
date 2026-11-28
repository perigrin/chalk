our $x = 1; sub c { $x = 5; 2 } sub f { my @a = @_; "@a" } print f($x, c()), "\n";
