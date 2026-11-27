our $x = 1; sub c { $x = 3; 2 } sub cp { my @c = @_; "@c" } print cp($x, c()), "\n";
