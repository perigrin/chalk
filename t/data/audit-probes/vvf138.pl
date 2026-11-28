my @a = (1,2,3); sub c { $a[0] = 9; 0 } my @l = (@a[0,1], c()); print "@l\n";
