our $x = 1; our $y = 0; sub c { $x = 3; 2 } my @l = (($y or $x), c()); print "@l\n";
