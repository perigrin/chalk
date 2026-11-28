our $x = 1; sub c { $x = 3; 2 } my @l = ((reverse 0, $x), c()); print "@l\n";
