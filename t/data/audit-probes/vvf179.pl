our $x = 1; our $y = 7; sub c { $x = 3; 2 } my @l = (($x ? $y : 0), c()); print "@l\n";
