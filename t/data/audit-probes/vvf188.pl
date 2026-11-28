our $x = 1; sub c { $x = 3; 2 } my @l = (do { $x; }, c()); print "@l\n";
