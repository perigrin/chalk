our $x = 1; sub c { $x = 3; 4 } my @l = ($x .. c()); print "@l\n";
