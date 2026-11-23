my $x=1; sub f { $x=5; 1 } sub show { "@_" } print show($x, f(), $x), "\n";
