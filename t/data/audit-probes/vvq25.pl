our $v = 1; sub c { $v = 9; 0 } my @l = ($main::v, c()); print "@l\n";
