our $x = 1; sub c { $x = 3; 2 } my @l = ((($x, 5))[0, 1], c()); print "@l\n";
