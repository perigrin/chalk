our $x = 1; sub c { $x = 3; 2 } my @l = (($x // 9), c()); print "@l\n";
