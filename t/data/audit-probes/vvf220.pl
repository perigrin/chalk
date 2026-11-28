our @t = (1); sub c { $t[0] = 7; 2 } my @l = ($t[0] + 0, c()); print "@l\n";
