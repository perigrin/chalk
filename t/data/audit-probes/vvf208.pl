our $x = 1; our $t; sub c { $t = 3; 2 } my @l = (($t = $x), c()); print "@l\n";
