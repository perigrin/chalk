my @a = (1,2,3); sub c { push @a, 9; 0 } my @l = (scalar(@a), c()); print "@l\n";
