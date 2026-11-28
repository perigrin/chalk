our $x = 0; sub c { $x = 3; 2 } my @l = (($x or 0), c()); print "@l\n";
