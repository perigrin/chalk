our $x = 1; sub c { $x = 3; 2 } sub g { $_[0] } my @l = (g($x), c()); print "@l\n";
