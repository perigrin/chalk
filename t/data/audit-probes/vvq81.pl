our $x = 1; sub c { $x = 3; 2 } my @l = ($x x 2, c()); print "@l\n";
