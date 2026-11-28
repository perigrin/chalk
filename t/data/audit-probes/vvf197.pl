our $x = 1; sub c { $x = 3; 2 } sub g { @_ } my @l = (g($x), c()); print "@l\n";
