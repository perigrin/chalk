our $x = 1; sub c { $x = 3; 2 } sub idx { $_[0] } my @l = (idx($x), c()); print "@l\n";
