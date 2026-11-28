our $v = 1; our $r = \$v; sub c { $v = 9; 0 } my @l = ($$r, c()); print "@l\n";
