our $x = 1; our $y = 1; sub c { $x = 3; 2 } my @l = (($y and $x), c()); print "@l\n";
