my $x = 1; sub c { $x = 7; 0 } sub f { "@_" } print f($x = 4, c()), "\n";
