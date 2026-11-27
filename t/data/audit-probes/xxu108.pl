our $x = 1; sub c { $x = 3; 2 } sub lst { @_ } my @l = (lst($x), c()); print "@l\n";
