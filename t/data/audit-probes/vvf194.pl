our $x = 1; sub c { $x = 3; 2 } sub g { $x } my @l = (g(), c()); print "@l\n";
