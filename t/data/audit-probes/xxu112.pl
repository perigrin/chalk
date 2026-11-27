our $x = 1; sub c { $x = 3; 2 } my @l = ((local $x = 7), c()); print "@l $x\n";
