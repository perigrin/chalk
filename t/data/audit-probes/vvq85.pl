our @a = (1,2); sub c { $a[0] = 3; 2 } my @l = ((@a) x 2, c()); print "@l\n";
