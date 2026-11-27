our $x = 1; sub c { $x = 3; 2 } my @a = (0,0,0,0); splice(@a, 0, 0, $x, c()); print "@a\n";
