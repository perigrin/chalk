our $v = 1; sub c { $v = 9; 0 } my @l = (${\ $v}, c()); print "@l\n";
