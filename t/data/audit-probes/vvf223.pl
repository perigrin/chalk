our @t = (1); our $i = 0; sub c { $i = 1; $t[1] = 7; 2 } my @l = ($t[$i], c()); print "@l\n";
