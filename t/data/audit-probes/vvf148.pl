my @a = (1,2,3); sub c { push @a, 9; 0 } my @l = (@a, c()); print "@l\n";
