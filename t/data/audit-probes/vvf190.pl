our $x = 1; sub c { $x = 3; 2 } my @l = (do { if (1) { $x } }, c()); print "@l\n";
