our $x = 1; our $y = 1; sub c { $y = 0; $x = 3; 2 } my @l = (($y && $x), c()); print "@l\n";
