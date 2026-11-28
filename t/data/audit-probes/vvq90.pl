our $x = 1; our $y; sub c { $x = 3; 2 } my @l = (($y // $x), c()); print "@l\n";
