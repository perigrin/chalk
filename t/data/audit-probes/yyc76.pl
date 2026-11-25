my $x="a"; sub f { $x="z"; "b" } sub g { "@_" } print g($x, f()), "\n";
