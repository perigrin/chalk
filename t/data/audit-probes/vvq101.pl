our $x = 1; our $y = 1; our $z = 1; sub c { $x = 3; 2 } my @l = (($z && $y && $x), c()); print "@l\n";
