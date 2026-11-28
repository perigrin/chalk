our $x = 1; sub c { $x = 3; 2 } my @l = (($x) x 1, c()); print "@l\n";
