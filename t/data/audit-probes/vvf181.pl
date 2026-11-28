our $x = 1; sub c { $x = 3; 2 } my @l = (($x and 1), c()); print "@l\n";
