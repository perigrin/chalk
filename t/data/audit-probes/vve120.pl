my $x = 1; sub c { $x = 5; 2 } sub f { "@_" } print f("$x", c(), $x), "\n";
