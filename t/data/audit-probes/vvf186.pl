our $x = 1; sub c { $x = 3; 2 } my @l = ((!1 || $x || 0), c()); print "@l\n";
