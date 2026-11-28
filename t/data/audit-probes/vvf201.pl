our $x = 1; sub c { $x = 3; 2 } my @l = ((sort $x, 0), c()); print "@l\n";
