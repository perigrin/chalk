our @x = (1); sub c { push @x, 3; 2 } my @l = (scalar(@x), c()); print "@l\n";
